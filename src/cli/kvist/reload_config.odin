package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import kvist "../../odin/kvist"

RELOAD_CACHE_DIR :: "reload-apps"

Reload_App_Config :: struct {
    state_type:     string,
    version:        string,
    reload_prefix:  string,
    run_name:       string,
    init_name:      string,
    on_load_name:   string,
    on_unload_name: string,
    package_name:   string,
}

Reload_App_Paths :: struct {
    root_dir:      string,
    app_dir:       string,
    module_dir:    string,
    host_dir:      string,
    app_odin:      string,
    module_odin:   string,
    host_odin:     string,
    module_binary: string,
}

Reload_Exec_Paths :: struct {
    root_dir:  string,
    app_dir:   string,
    main_dir:  string,
    app_odin:  string,
    main_odin: string,
}

Reload_Build_Result :: struct {
    ok:        bool,
    exit_code: int,
}

reload_app_symbol_name :: proc(text: string) -> string {
    symbol_text := text
    if len(symbol_text) > 0 &&
       symbol_text[len(symbol_text)-1] == ':' {
        symbol_text = symbol_text[:len(symbol_text)-1]
    }
    mapped := kvist.map_name(symbol_text)
    defer delete(mapped)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for ch in mapped {
        if ch == '/' || ch == '.' {
            strings.write_string(&builder, "__")
        } else {
            strings.write_rune(&builder, ch)
        }
    }
    return strings.clone(strings.to_string(builder))
}

delete_reload_app_paths :: proc(paths: ^Reload_App_Paths) {
    if paths.root_dir != "" {
        delete(paths.root_dir)
    }
    if paths.app_dir != "" {
        delete(paths.app_dir)
    }
    if paths.module_dir != "" {
        delete(paths.module_dir)
    }
    if paths.host_dir != "" {
        delete(paths.host_dir)
    }
    if paths.app_odin != "" {
        delete(paths.app_odin)
    }
    if paths.module_odin != "" {
        delete(paths.module_odin)
    }
    if paths.host_odin != "" {
        delete(paths.host_odin)
    }
    if paths.module_binary != "" {
        delete(paths.module_binary)
    }
    paths^ = Reload_App_Paths{}
}

delete_reload_exec_paths :: proc(paths: ^Reload_Exec_Paths) {
    if paths.root_dir != "" {
        delete(paths.root_dir)
    }
    if paths.app_dir != "" {
        delete(paths.app_dir)
    }
    if paths.main_dir != "" {
        delete(paths.main_dir)
    }
    if paths.app_odin != "" {
        delete(paths.app_odin)
    }
    if paths.main_odin != "" {
        delete(paths.main_odin)
    }
    paths^ = Reload_Exec_Paths{}
}

reload_cache_key :: proc(text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    for ch in text {
        switch ch {
        case '/', '\\', ':', '.', ' ', '-':
            strings.write_byte(&builder, '_')
        case '?':
            strings.write_string(&builder, "_p")
        case '!':
            strings.write_string(&builder, "_bang")
        case:
            strings.write_rune(&builder, ch)
        }
    }

    return strings.clone(strings.to_string(builder))
}

reload_app_default_root :: proc(input: string) -> string {
    cache_dir := cache_dir_or_exit()
    input_abs, abs_err := os.get_absolute_path(input, context.allocator)
    if abs_err != nil {
        fmt.eprintln("failed to resolve reload input path")
        os.exit(1)
    }
    defer delete(input_abs)

    cache_key_source := strings.clone(input)
    if repo_root_value, repo_ok := kvist.repo_root_for_path(input_abs); repo_ok {
        defer delete(repo_root_value)
        if relative, rel_err := os.get_relative_path(repo_root_value, input_abs, context.allocator); rel_err == nil {
            delete(cache_key_source)
            cache_key_source = relative
        }
    } else {
        delete(cache_key_source)
        cache_key_source = strings.clone(input_abs)
    }
    defer delete(cache_key_source)

    cache_key := reload_cache_key(cache_key_source)
    defer delete(cache_key)

    app_root, join_err := os.join_path({cache_dir, RELOAD_CACHE_DIR, cache_key}, context.allocator)
    delete(cache_dir)
    if join_err != nil {
        fmt.eprintln("failed to create reload app cache path")
        os.exit(1)
    }
    return app_root
}

reload_exec_default_root :: proc(input: string) -> string {
    root := reload_app_default_root(input)
    prod_root, join_err := os.join_path({root, "prod"}, context.allocator)
    delete(root)
    if join_err != nil {
        fmt.eprintln("failed to create reload production cache path")
        os.exit(1)
    }
    return prod_root
}

reload_app_relative_path_or_exit :: proc(base_dir, target: string) -> string {
    path, err := os.get_relative_path(base_dir, target, context.allocator)
    if err != nil {
        path = strings.clone(target)
    }
    normalized, allocated := strings.replace_all(path, "\\", "/", context.allocator)
    if allocated {
        delete(path)
        return normalized
    }
    out := strings.clone(path)
    delete(path)
    return out
}

reload_app_absolute_path_or_exit :: proc(path: string) -> string {
    if os.is_absolute_path(path) {
        return strings.clone(path)
    }
    cwd, cwd_err := os.get_working_directory(context.allocator)
    if cwd_err != nil {
        fmt.eprintln("failed to read working directory")
        os.exit(1)
    }
    defer delete(cwd)
    absolute, join_err := os.join_path({cwd, path}, context.allocator)
    if join_err != nil {
        fmt.eprintln("failed to build absolute reload app path")
        os.exit(1)
    }
    return absolute
}

reload_app_canonical_root_or_exit :: proc(path: string) -> string {
    absolute := reload_app_absolute_path_or_exit(path)
    defer delete(absolute)

    if !os.exists(absolute) {
        err := os.make_directory_all(absolute)
        if err != nil {
            fmt.eprintln("failed to create reload app directory: ", absolute)
            os.exit(1)
        }
    }

    canonical, canonical_err := os.get_absolute_path(absolute, context.allocator)
    if canonical_err != nil {
        fmt.eprintln("failed to canonicalize reload app directory: ", absolute)
        os.exit(1)
    }
    return canonical
}

reload_app_config_from_source :: proc(input, source: string) -> (config: Reload_App_Config, err: kvist.Compile_Error, ok: bool) {
    forms, read_err, read_ok := kvist.read_top_forms(source)
    if !read_ok {
        return config, read_err, false
    }
    defer kvist.delete_borrowed_cst_top_form_slice(&forms)

    config.version = strings.clone("dev")
    config.reload_prefix = strings.clone("reload")
    found_reload_state := false

    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
            continue
        }

        if form.items[0].text == "package" && len(form.items) == 2 && form.items[1].kind == .Symbol {
            if config.package_name == "" {
                config.package_name = kvist.map_name(form.items[1].text)
            }
            continue
        }
        if form.items[0].text == "import" {
            if len(form.items) == 2 && form.items[1].kind == .String {
                import_path := kvist.import_path_text(form.items[1])
                is_reload_import := import_path == "kvist:reload"
                delete(import_path)
                if is_reload_import {
                    continue
                }
            }
            if len(form.items) == 3 && form.items[1].kind == .Symbol &&
               form.items[2].kind == .String {
                import_path := kvist.import_path_text(form.items[2])
                is_reload_import := import_path == "kvist:reload"
                delete(import_path)
                if is_reload_import {
                    if config.reload_prefix != "" {
                        delete(config.reload_prefix)
                    }
                    config.reload_prefix =
                        kvist.map_name(form.items[1].text)
                    continue
                }
            }
        }

        switch form.items[0].text {
        case "def":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                name := reload_app_symbol_name(form.items[1].text)
                defer delete(name)
                if name == "Reload_State" {
                    found_reload_state = true
                    if config.state_type != "" {
                        delete(config.state_type)
                    }
                    config.state_type = strings.clone("Reload_State")
                    continue
                }
                if name == "Reload_Version" && len(form.items) >= 3 &&
                   form.items[len(form.items)-1].kind == .String {
                    if config.version != "" {
                        delete(config.version)
                    }
                    config.version =
                        kvist.unquote_string(
                            form.items[len(form.items)-1].text,
                        )
                    continue
                }
            }
        case "defn":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                name := reload_app_symbol_name(form.items[1].text)
                defer delete(name)
                switch name {
                case "run":
                    if config.run_name != "" {
                        delete(config.run_name)
                    }
                    config.run_name = strings.clone(name)
                case "init":
                    if config.init_name != "" {
                        delete(config.init_name)
                    }
                    config.init_name = strings.clone(name)
                case "on_load":
                    if config.on_load_name != "" {
                        delete(config.on_load_name)
                    }
                    config.on_load_name = strings.clone(name)
                case "on_unload":
                    if config.on_unload_name != "" {
                        delete(config.on_unload_name)
                    }
                    config.on_unload_name = strings.clone(name)
                case:
                }
            }
        }
    }

    if !found_reload_state {
        return config, kvist.Compile_Error{message = "reload mode requires a top-level `(def Reload_State <State_Type>)` alias"}, false
    }
    if config.run_name == "" {
        return config, kvist.Compile_Error{message = "reload mode requires a top-level `run` function"}, false
    }
    if config.package_name == "" {
        config.package_name = strings.clone("main")
    }
    return config, kvist.Compile_Error{}, true
}

reload_app_file_has_config :: proc(path: string) -> bool {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return false
    }
    defer delete(data)

    _, _, ok := reload_app_config_from_source(path, string(data))
    return ok
}

reload_app_conventional_adapter_for_input :: proc(input: string) -> (resolved_input: string, ok: bool) {
    input_abs, abs_err := os.get_absolute_path(input, context.allocator)
    if abs_err != nil {
        return "", false
    }
    defer delete(input_abs)

    repo_root, repo_ok := kvist.repo_root_for_path(input_abs)
    if repo_ok {
        defer delete(repo_root)
    }

    dir, _ := os.split_path(input_abs)
    if dir == "" {
        return "", false
    }
    current := strings.clone(dir)

    for {
        candidate, join_err := os.join_path({current, "reload.kvist"}, context.allocator)
        if join_err == nil {
            if candidate != input_abs && reload_app_file_has_config(candidate) {
                delete(current)
                return candidate, true
            }
            delete(candidate)
        }

        if repo_ok && current == repo_root {
            break
        }
        parent, _ := os.split_path(strings.trim_right(current, "/"))
        if parent == "" || parent == current {
            break
        }
        delete(current)
        current = strings.clone(parent)
    }

    delete(current)
    return "", false
}

reload_app_primary_input :: proc(input: string) -> (resolved_input: string, ok: bool) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    _, _, config_ok := reload_app_config_from_source(input, data)
    if config_ok {
        return strings.clone(input), true
    }

    forms, _, read_ok := kvist.read_top_forms(data)
    if !read_ok {
        return "", false
    }
    package_name := ""
    for top in forms {
        form := top.form
        if form.kind == .List && len(form.items) == 2 && form.items[0].kind == .Symbol && form.items[0].text == "package" && form.items[1].kind == .Symbol {
            package_name = form.items[1].text
            break
        }
    }
    if package_name == "" {
        return "", false
    }

    dir, _ := os.split_path(input)
    if dir == "" {
        return "", false
    }
    entries, dir_err := os.read_directory_by_path(dir, -1, context.allocator)
    if dir_err != nil {
        return "", false
    }
    defer delete(entries)

    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".kvist") {
            continue
        }
        file_path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil || file_path == input {
            continue
        }
        file_data, file_err := os.read_entire_file_from_path(file_path, context.allocator)
        if file_err != nil {
            continue
        }
        file_source := string(file_data)
        file_forms, _, ok_forms := kvist.read_top_forms(file_source)
        if !ok_forms {
            continue
        }
        file_package_name := ""
        for top in file_forms {
            form := top.form
            if form.kind == .List && len(form.items) == 2 && form.items[0].kind == .Symbol && form.items[0].text == "package" && form.items[1].kind == .Symbol {
                file_package_name = form.items[1].text
                break
            }
        }
        if file_package_name != package_name {
            continue
        }
        _, _, file_config_ok := reload_app_config_from_source(file_path, file_source)
        if file_config_ok {
            return strings.clone(file_path), true
        }
    }

    if adapter, adapter_ok := reload_app_conventional_adapter_for_input(input); adapter_ok {
        return adapter, true
    }

    return "", false
}

reload_app_paths :: proc(root_dir: string) -> Reload_App_Paths {
    app_dir, app_join_err := os.join_path({root_dir, "app"}, context.allocator)
    if app_join_err != nil {
        fmt.eprintln("failed to build reload app app directory")
        os.exit(1)
    }
    module_dir, module_join_err := os.join_path({root_dir, "module"}, context.allocator)
    if module_join_err != nil {
        fmt.eprintln("failed to build reload app module directory")
        os.exit(1)
    }
    host_dir, host_join_err := os.join_path({root_dir, "host"}, context.allocator)
    if host_join_err != nil {
        fmt.eprintln("failed to build reload app host directory")
        os.exit(1)
    }
    app_odin, app_odin_err := os.join_path({app_dir, "package.odin"}, context.allocator)
    if app_odin_err != nil {
        fmt.eprintln("failed to build reload app app output path")
        os.exit(1)
    }
    module_odin, module_odin_err := os.join_path({module_dir, "main.odin"}, context.allocator)
    if module_odin_err != nil {
        fmt.eprintln("failed to build reload app module output path")
        os.exit(1)
    }
    host_odin, host_odin_err := os.join_path({host_dir, "main.odin"}, context.allocator)
    if host_odin_err != nil {
        fmt.eprintln("failed to build reload app host output path")
        os.exit(1)
    }
    module_binary_base, module_binary_base_err := os.join_path({module_dir, "reload_app"}, context.allocator)
    if module_binary_base_err != nil {
        fmt.eprintln("failed to build reload app module binary path")
        os.exit(1)
    }
    module_binary := strings.clone(fmt.tprintf("%s.%s", module_binary_base, dynlib.LIBRARY_FILE_EXTENSION))
    delete(module_binary_base)

    return Reload_App_Paths{
        root_dir = strings.clone(root_dir),
        app_dir = app_dir,
        module_dir = module_dir,
        host_dir = host_dir,
        app_odin = app_odin,
        module_odin = module_odin,
        host_odin = host_odin,
        module_binary = module_binary,
    }
}

reload_exec_paths :: proc(root_dir: string) -> Reload_Exec_Paths {
    app_dir, app_join_err := os.join_path({root_dir, "app"}, context.allocator)
    if app_join_err != nil {
        fmt.eprintln("failed to build reload app directory")
        os.exit(1)
    }
    main_dir, main_join_err := os.join_path({root_dir, "main"}, context.allocator)
    if main_join_err != nil {
        fmt.eprintln("failed to build reload main directory")
        os.exit(1)
    }
    app_odin, app_odin_err := os.join_path({app_dir, "package.odin"}, context.allocator)
    if app_odin_err != nil {
        fmt.eprintln("failed to build reload app output path")
        os.exit(1)
    }
    main_odin, main_odin_err := os.join_path({main_dir, "main.odin"}, context.allocator)
    if main_odin_err != nil {
        fmt.eprintln("failed to build reload main output path")
        os.exit(1)
    }
    return Reload_Exec_Paths{
        root_dir = strings.clone(root_dir),
        app_dir = app_dir,
        main_dir = main_dir,
        app_odin = app_odin,
        main_odin = main_odin,
    }
}

ensure_reload_app_dirs_or_exit :: proc(paths: Reload_App_Paths) {
    if !os.exists(paths.root_dir) {
        err := os.make_directory_all(paths.root_dir)
        if err != nil {
            fmt.eprintln("failed to create reload app directory: ", paths.root_dir)
            os.exit(1)
        }
    }
    if !os.exists(paths.app_dir) {
        err := os.make_directory_all(paths.app_dir)
        if err != nil {
            fmt.eprintln("failed to create reload app directory: ", paths.app_dir)
            os.exit(1)
        }
    }
    if !os.exists(paths.module_dir) {
        err := os.make_directory_all(paths.module_dir)
        if err != nil {
            fmt.eprintln("failed to create reload app directory: ", paths.module_dir)
            os.exit(1)
        }
    }
    if !os.exists(paths.host_dir) {
        err := os.make_directory_all(paths.host_dir)
        if err != nil {
            fmt.eprintln("failed to create reload app directory: ", paths.host_dir)
            os.exit(1)
        }
    }
}

ensure_reload_exec_dirs_or_exit :: proc(paths: Reload_Exec_Paths) {
    if !os.exists(paths.root_dir) {
        err := os.make_directory_all(paths.root_dir)
        if err != nil {
            fmt.eprintln("failed to create reload directory: ", paths.root_dir)
            os.exit(1)
        }
    }
    if !os.exists(paths.app_dir) {
        err := os.make_directory_all(paths.app_dir)
        if err != nil {
            fmt.eprintln("failed to create reload directory: ", paths.app_dir)
            os.exit(1)
        }
    }
    if !os.exists(paths.main_dir) {
        err := os.make_directory_all(paths.main_dir)
        if err != nil {
            fmt.eprintln("failed to create reload directory: ", paths.main_dir)
            os.exit(1)
        }
    }
}
