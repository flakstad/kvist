package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import kvist "../../src/kvist"

RELOAD_CACHE_DIR :: "reload-apps"

Reload_App_Config :: struct {
    state_type:     string,
    version:        string,
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
    mapped := kvist.map_name(text)
    defer delete(mapped)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for ch in mapped {
        if ch == '/' {
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
        fmt.eprintln("failed to compute relative path")
        os.exit(1)
    }
    return path
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

    config.version = strings.clone("dev")
    found_defstate := false

    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
            continue
        }

        if form.items[0].text == "package" && len(form.items) == 2 && form.items[1].kind == .Symbol {
            if config.package_name == "" {
                config.package_name = strings.clone(kvist.map_name(form.items[1].text))
            }
            continue
        }
        if form.items[0].text == "import" {
            if len(form.items) == 2 && form.items[1].kind == .String && kvist.import_path_text(form.items[1]) == "kvist:reload" {
                continue
            }
            if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String && kvist.import_path_text(form.items[2]) == "kvist:reload" {
                if kvist.map_name(form.items[1].text) != "reload" {
                    return config, kvist.Compile_Error{message = "kvist:reload must be imported as reload in reload mode", span = form.items[1].span}, false
                }
                continue
            }
        }

        switch form.items[0].text {
        case "defstate":
            if found_defstate {
                return config, kvist.Compile_Error{message = "defstate must appear at most once in reload dev mode", span = form.span}, false
            }
            metadata_only := len(form.items) == 3 && form.items[2].kind == .Brace
            if !metadata_only && len(form.items) != 4 && len(form.items) != 5 {
                return config, kvist.Compile_Error{message = "reload dev mode requires defstate with either metadata only or fields plus metadata brace forms", span = form.span}, false
            }
            if form.items[1].kind != .Symbol {
                return config, kvist.Compile_Error{message = "defstate expects a symbol name", span = form.items[1].span}, false
            }
            fields_index := 2
            meta_index := 3
            if metadata_only {
                meta_index = 2
            } else if len(form.items) == 5 {
                if form.items[2].kind != .String {
                    return config, kvist.Compile_Error{message = "defstate docstring must be a string literal", span = form.items[2].span}, false
                }
                fields_index = 3
                meta_index = 4
            }
            if !metadata_only && form.items[fields_index].kind != .Brace {
                return config, kvist.Compile_Error{message = "defstate fields must be a brace form", span = form.items[fields_index].span}, false
            }
            if form.items[meta_index].kind != .Brace {
                return config, kvist.Compile_Error{message = "defstate reload metadata must be a brace form", span = form.items[meta_index].span}, false
            }
            found_defstate = true
            config.state_type = reload_app_symbol_name(form.items[1].text)
            meta := form.items[meta_index]
            i := 0
            for i < len(meta.items) {
                if i+1 >= len(meta.items) {
                    return config, kvist.Compile_Error{message = "defstate reload metadata has a missing value", span = meta.span}, false
                }
                key_form := meta.items[i]
                value := meta.items[i+1]
                if key_form.kind != .Symbol || len(key_form.text) < 2 || key_form.text[len(key_form.text)-1] != ':' {
                    return config, kvist.Compile_Error{message = "defstate reload metadata expects field labels like run:", span = key_form.span}, false
                }
                key := key_form.text[:len(key_form.text)-1]
                switch key {
                case "run":
                    if value.kind != .Symbol {
                        return config, kvist.Compile_Error{message = "defstate run: must be a symbol", span = value.span}, false
                    }
                    if config.run_name != "" {
                        delete(config.run_name)
                    }
                    config.run_name = reload_app_symbol_name(value.text)
                case "init":
                    if value.kind == .Nil {
                        config.init_name = ""
                    } else {
                        if value.kind != .Symbol {
                            return config, kvist.Compile_Error{message = "defstate init: must be a symbol or nil", span = value.span}, false
                        }
                        if config.init_name != "" {
                            delete(config.init_name)
                        }
                        config.init_name = reload_app_symbol_name(value.text)
                    }
                case "on-load":
                    if value.kind == .Nil {
                        config.on_load_name = ""
                    } else {
                        if value.kind != .Symbol {
                            return config, kvist.Compile_Error{message = "defstate on-load: must be a symbol or nil", span = value.span}, false
                        }
                        if config.on_load_name != "" {
                            delete(config.on_load_name)
                        }
                        config.on_load_name = reload_app_symbol_name(value.text)
                    }
                case "on-unload":
                    if value.kind == .Nil {
                        config.on_unload_name = ""
                    } else {
                        if value.kind != .Symbol {
                            return config, kvist.Compile_Error{message = "defstate on-unload: must be a symbol or nil", span = value.span}, false
                        }
                        if config.on_unload_name != "" {
                            delete(config.on_unload_name)
                        }
                        config.on_unload_name = reload_app_symbol_name(value.text)
                    }
                case "version":
                    if value.kind != .String {
                        return config, kvist.Compile_Error{message = "defstate version: must be a string", span = value.span}, false
                    }
                    if config.version != "" {
                        delete(config.version)
                    }
                    config.version = kvist.unquote_string(value.text)
                case:
                    return config, kvist.Compile_Error{message = fmt.tprintf("unsupported defstate reload metadata option: %s:", key), span = key_form.span}, false
                }
                i += 2
            }
        }
    }

    if !found_defstate {
        return config, kvist.Compile_Error{message = "missing defstate declaration"}, false
    }
    if config.run_name == "" {
        return config, kvist.Compile_Error{message = "defstate reload metadata requires run:"}, false
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
    defer delete(result.source_map)
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
    strings.write_string(&builder, ")(state)\n    app_host := (^app.reload__Run_Host")
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
    strings.write_string(&builder, "    version:  proc \"c\" () -> cstring `dynlib:\"kvist_reload_app_version\"`,\n")
    strings.write_string(&builder, "    run:      proc \"c\" (state: rawptr, host: rawptr) `dynlib:\"olive_reload_app_run\"`,\n")
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
        strings.write_string(&builder, "    case .Reload_Failed:\n        fmt.eprintf(\"[reload] reload failed: %s\\n\", event.message)\n")
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

write_reload_app_generated_sources_or_exit :: proc(input: string, config: Reload_App_Config, paths: Reload_App_Paths, json_output := false) {
    input_abs, abs_err := os.get_absolute_path(input, context.allocator)
    if abs_err != nil {
        fmt.eprintln("failed to resolve input path")
        os.exit(1)
    }
    defer delete(input_abs)

    repo_root_value, repo_ok := kvist.repo_root_for_path(input_abs)
    if !repo_ok {
        fmt.eprintln("failed to locate repo root for reload app generation")
        os.exit(1)
    }
    repo_root := repo_root_value
    defer delete(repo_root)

    olive_reload_path, olive_reload_err := os.join_path({repo_root, "src", "olive_reload"}, context.allocator)
    if olive_reload_err != nil {
        fmt.eprintln("failed to build olive_reload import path")
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

run_process_inherited :: proc(command: []string, working_dir: string) -> int {
    process, err := os.process_start(os.Process_Desc{
        command = command,
        working_dir = working_dir,
        stdin = os.stdin,
        stdout = os.stdout,
        stderr = os.stderr,
    })
    if err != nil {
        fmt.eprintln("failed to start process: ", command[0])
        return 1
    }
    state, wait_err := os.process_wait(process)
    if wait_err != nil {
        fmt.eprintln("failed to wait for process: ", command[0])
        return 1
    }
    if state.exited {
        return state.exit_code
    }
    return 1
}

build_odin_package :: proc(package_dir, output_path: string, build_mode := "") -> int {
	args := make([dynamic]string, 0, 6)
	defer delete(args)
	append(&args, "odin", "build", package_dir)
	if build_mode != "" {
        append(&args, build_mode)
    }
	append(&args, fmt.tprintf("-out:%s", output_path))
	return run_process_inherited(args[:], ".")
}

build_reload_app_module :: proc(paths: Reload_App_Paths) -> int {
	module_tmp := strings.clone(fmt.tprintf("%s.tmp", paths.module_binary))
	defer delete(module_tmp)

	exit_code := build_odin_package(paths.module_dir, module_tmp, "-build-mode:dll")
	if exit_code != 0 {
		if os.exists(module_tmp) {
			_ = os.remove(module_tmp)
		}
		return exit_code
	}
	if os.exists(paths.module_binary) {
		_ = os.remove(paths.module_binary)
	}
	if os.rename(module_tmp, paths.module_binary) != nil {
		fmt.eprintln("failed to publish reload module: ", paths.module_binary)
		return 1
	}
	return 0
}

build_odin_package_or_exit :: proc(package_dir, output_path: string, build_mode := "") {
	exit_code := build_odin_package(package_dir, output_path, build_mode)
	if exit_code != 0 {
		os.exit(exit_code)
	}
}

run_odin_package_or_exit :: proc(package_dir: string) {
	exit_code := run_process_inherited({"odin", "run", package_dir}, ".")
	os.exit(exit_code)
}

reload_watch_root_for_input :: proc(input: string) -> string {
	dir, _ := os.split_path(input)
	if dir == "" {
		return strings.clone(".")
	}
	return strings.clone(dir)
}

reload_watch_skip_dir :: proc(name: string) -> bool {
	return name == ".git" || name == ".kvist-cache" || name == ".worktrees" || name == "build"
}

newest_kvist_write_time :: proc(path: string) -> (time.Time, bool) {
	info, stat_err := os.stat(path, context.temp_allocator)
	if stat_err != nil {
		return {}, false
	}
	if info.type == .Regular {
		if strings.has_suffix(info.name, ".kvist") {
			return info.modification_time, true
		}
		return {}, false
	}
	if info.type != .Directory {
		return {}, false
	}

	newest := time.Time{}
	found := false
	entries, read_err := os.read_directory_by_path(path, -1, context.temp_allocator)
	if read_err != nil {
		return {}, false
	}
	for entry in entries {
		if entry.name == "." || entry.name == ".." || reload_watch_skip_dir(entry.name) {
			continue
		}
		child := entry.fullpath
		owned_child := false
		if child == "" {
			child, _ = os.join_path({path, entry.name}, context.temp_allocator)
			owned_child = true
		}
		child_time, child_found := newest_kvist_write_time(child)
		if owned_child {
			delete(child, context.temp_allocator)
		}
		if child_found {
			if !found || time.time_to_unix_nano(child_time) > time.time_to_unix_nano(newest) {
				newest = child_time
			}
			found = true
		}
	}
	return newest, found
}

reload_app_rebuild_command :: proc(input, root_dir: string, json_output: bool) -> [dynamic]string {
	args := make([dynamic]string, 0, 8)
	append(&args, os.args[0], "dev", "--reload", input, "--rebuild", "--generated-dir", root_dir)
	if json_output {
		append(&args, "--json")
	}
	return args
}

reload_app_rebuild_for_watch :: proc(input, root_dir: string, json_output: bool) -> int {
	args := reload_app_rebuild_command(input, root_dir, json_output)
	defer delete(args)
	return run_process_inherited(args[:], ".")
}

run_odin_package_with_reload_watch :: proc(package_dir, input, root_dir: string, json_output: bool) -> int {
	watch_root := reload_watch_root_for_input(input)
	defer delete(watch_root)

	last_write, found := newest_kvist_write_time(watch_root)
	if !found {
		fmt.eprintln("[reload] watch found no .kvist files under: ", watch_root)
		return 1
	}

	process, err := os.process_start(os.Process_Desc{
		command = {"odin", "run", package_dir},
		working_dir = ".",
		stdin = os.stdin,
		stdout = os.stdout,
		stderr = os.stderr,
	})
	if err != nil {
		fmt.eprintln("failed to start process: odin")
		return 1
	}

	if !json_output {
		fmt.println("[reload] watching ", watch_root)
	}
	debounce := 150 * time.Millisecond
	for {
		state, wait_err := os.process_wait(process, timeout = 0)
		if wait_err == nil && state.exited {
			return state.exit_code
		}

		time.sleep(250 * time.Millisecond)
		current_write, current_found := newest_kvist_write_time(watch_root)
		if !current_found {
			continue
		}
		if time.time_to_unix_nano(current_write) == time.time_to_unix_nano(last_write) {
			continue
		}
		last_write = current_write
		time.sleep(debounce)
		settled_write, settled_found := newest_kvist_write_time(watch_root)
		if settled_found {
			last_write = settled_write
		}
		if !json_output {
			fmt.println("[reload] change detected; rebuilding module")
		}
		rebuild_status := reload_app_rebuild_for_watch(input, root_dir, json_output)
		if !json_output {
			if rebuild_status == 0 {
				fmt.println("[reload] build ok")
			} else {
				fmt.printf("[reload] build failed exit=%d; still watching\n", rebuild_status)
			}
		}
	}
}

print_reload_app_paths :: proc(input: string, paths: Reload_App_Paths) {
	fmt.println("mode=reload")
	fmt.println("input=", input)
	fmt.println("root_dir=", paths.root_dir)
	fmt.println("app_dir=", paths.app_dir)
	fmt.println("module_dir=", paths.module_dir)
	fmt.println("host_dir=", paths.host_dir)
	fmt.println("app_odin=", paths.app_odin)
	fmt.println("module_odin=", paths.module_odin)
	fmt.println("host_odin=", paths.host_odin)
	fmt.println("module_binary=", paths.module_binary)
	fmt.println("rebuild_command=kvist dev --reload ", input, " --rebuild")
	fmt.println("watch_command=kvist dev --reload ", input, " --watch")
	fmt.println("run_command=kvist dev --reload ", input)
}

json_write_escaped_string :: proc(builder: ^strings.Builder, value: string) {
	strings.write_byte(builder, '"')
	for ch in value {
		switch ch {
		case '\\':
			strings.write_string(builder, "\\\\")
		case '"':
			strings.write_string(builder, "\\\"")
		case '\n':
			strings.write_string(builder, "\\n")
		case '\r':
			strings.write_string(builder, "\\r")
		case '\t':
			strings.write_string(builder, "\\t")
		case:
			strings.write_rune(builder, ch)
		}
	}
	strings.write_byte(builder, '"')
}

json_write_key :: proc(builder: ^strings.Builder, key: string) {
	json_write_escaped_string(builder, key)
	strings.write_string(builder, ": ")
}

print_reload_app_paths_json :: proc(input: string, paths: Reload_App_Paths) {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "{\n")

    json_write_key(&builder, "mode")
    json_write_escaped_string(&builder, "reload")
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "input")
    json_write_escaped_string(&builder, input)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "root_dir")
    json_write_escaped_string(&builder, paths.root_dir)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "app_dir")
    json_write_escaped_string(&builder, paths.app_dir)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "module_dir")
    json_write_escaped_string(&builder, paths.module_dir)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "host_dir")
    json_write_escaped_string(&builder, paths.host_dir)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "app_odin")
    json_write_escaped_string(&builder, paths.app_odin)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "module_odin")
    json_write_escaped_string(&builder, paths.module_odin)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "host_odin")
    json_write_escaped_string(&builder, paths.host_odin)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "module_binary")
    json_write_escaped_string(&builder, paths.module_binary)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "rebuild_command")
    json_write_escaped_string(&builder, fmt.tprintf("kvist dev --reload %q --rebuild", input))
    strings.write_string(&builder, ",\n")

	json_write_key(&builder, "watch_command")
	json_write_escaped_string(&builder, fmt.tprintf("kvist dev --reload %q --watch", input))
	strings.write_string(&builder, ",\n")

	json_write_key(&builder, "run_command")
	json_write_escaped_string(&builder, fmt.tprintf("kvist dev --reload %q", input))
	strings.write_string(&builder, "\n}\n")

    fmt.print(strings.to_string(builder))
}

print_reload_rebuild_result_json :: proc(input: string, paths: Reload_App_Paths, result: Reload_Build_Result) {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "{\n")

    json_write_key(&builder, "mode")
    json_write_escaped_string(&builder, "reload")
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "action")
    json_write_escaped_string(&builder, "rebuild")
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "input")
    json_write_escaped_string(&builder, input)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "ok")
    if result.ok {
        strings.write_string(&builder, "true,\n")
    } else {
        strings.write_string(&builder, "false,\n")
    }

    json_write_key(&builder, "exit_code")
    fmt.sbprintf(&builder, "%d,\n", result.exit_code)

    json_write_key(&builder, "module_dir")
    json_write_escaped_string(&builder, paths.module_dir)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "module_odin")
    json_write_escaped_string(&builder, paths.module_odin)
    strings.write_string(&builder, ",\n")

    json_write_key(&builder, "module_binary")
    json_write_escaped_string(&builder, paths.module_binary)
    strings.write_string(&builder, "\n}\n")

    fmt.print(strings.to_string(builder))
}

reload_app_generate_and_build :: proc(input: string, generated_dir := "", rebuild_only, print_paths_only, json_output, watch: bool) {
    effective_input := strings.clone(input)
    defer delete(effective_input)
    resolved_input, resolved_ok := reload_app_primary_input(input)
    if resolved_ok {
        delete(effective_input)
        effective_input = resolved_input
    }
    data := read_source_or_exit(effective_input)
    defer delete(transmute([]byte)data)

    config, config_err, config_ok := reload_app_config_from_source(effective_input, data)
    if !config_ok {
        formatted := kvist.format_compile_error(effective_input, data, config_err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    root_dir := generated_dir
    if root_dir == "" {
        root_dir = reload_app_default_root(effective_input)
    } else {
        root_dir = strings.clone(root_dir)
    }
    defer delete(root_dir)

    root_abs := reload_app_canonical_root_or_exit(root_dir)
    defer delete(root_abs)

    paths := reload_app_paths(root_abs)
    defer delete_reload_app_paths(&paths)
    ensure_reload_app_dirs_or_exit(paths)

    compile_path_to_output_or_exit(effective_input, paths.app_odin)
    write_reload_app_generated_sources_or_exit(effective_input, config, paths, json_output && !rebuild_only && !print_paths_only)

    if print_paths_only {
        if json_output {
            print_reload_app_paths_json(effective_input, paths)
        } else {
            print_reload_app_paths(effective_input, paths)
        }
        return
    }

	module_build_exit_code := build_reload_app_module(paths)
	if module_build_exit_code != 0 {
		if rebuild_only && json_output {
			print_reload_rebuild_result_json(effective_input, paths, Reload_Build_Result{ok = false, exit_code = module_build_exit_code})
		}
        os.exit(module_build_exit_code)
    }
    if rebuild_only {
        if json_output {
            print_reload_rebuild_result_json(effective_input, paths, Reload_Build_Result{ok = true, exit_code = 0})
		}
		return
	}

	if watch {
		os.exit(run_odin_package_with_reload_watch(paths.host_dir, effective_input, paths.root_dir, json_output))
	}

	run_odin_package_or_exit(paths.host_dir)
}

run_odin_package_command :: proc(package_dir, odin_command: string) -> int {
    return run_process_inherited({"odin", odin_command, package_dir}, ".")
}

reload_app_generate_and_execute :: proc(input: string, odin_command: string, generated_dir := "") -> int {
    effective_input := strings.clone(input)
    defer delete(effective_input)
    resolved_input, resolved_ok := reload_app_primary_input(input)
    if resolved_ok {
        delete(effective_input)
        effective_input = resolved_input
    }
    data := read_source_or_exit(effective_input)
    defer delete(transmute([]byte)data)

    config, config_err, config_ok := reload_app_config_from_source(effective_input, data)
    if !config_ok {
        formatted := kvist.format_compile_error(effective_input, data, config_err)
        fmt.eprint(formatted)
        delete(formatted)
        return 1
    }

    root_dir := generated_dir
    if root_dir == "" {
        root_dir = reload_exec_default_root(effective_input)
    } else {
        root_dir = strings.clone(generated_dir)
    }
    defer delete(root_dir)

    root_abs := reload_app_canonical_root_or_exit(root_dir)
    defer delete(root_abs)

    paths := reload_exec_paths(root_abs)
    defer delete_reload_exec_paths(&paths)
    ensure_reload_exec_dirs_or_exit(paths)

    compile_path_to_output_or_exit(effective_input, paths.app_odin)

    input_abs, abs_err := os.get_absolute_path(effective_input, context.allocator)
    if abs_err != nil {
        fmt.eprintln("failed to resolve reload input path")
        return 1
    }
    defer delete(input_abs)

    repo_root_value, repo_ok := kvist.repo_root_for_path(input_abs)
    if !repo_ok {
        fmt.eprintln("failed to locate repo root for reload generation")
        return 1
    }
    repo_root := repo_root_value
    defer delete(repo_root)

    reload_runtime_path, runtime_join_err := os.join_path({repo_root, "src", "olive_reload"}, context.allocator)
    if runtime_join_err != nil {
        fmt.eprintln("failed to build reload runtime import path")
        return 1
    }
    defer delete(reload_runtime_path)

    main_app_import := reload_app_relative_path_or_exit(paths.main_dir, paths.app_dir)
    defer delete(main_app_import)
    main_reload_runtime_import := reload_app_relative_path_or_exit(paths.main_dir, reload_runtime_path)
    defer delete(main_reload_runtime_import)

    main_source := reload_app_main_source(config, main_app_import, main_reload_runtime_import)
    defer delete(main_source)
    write_output_or_exit(paths.main_odin, main_source)

    return run_odin_package_command(paths.main_dir, odin_command)
}

source_declares_reload_app :: proc(input: string) -> bool {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    _, _, ok := reload_app_config_from_source(input, data)
    return ok
}

parse_dev_command :: proc() {
    if len(os.args) < 4 {
        print_usage()
        os.exit(2)
    }

    reload_mode := false
	rebuild_only := false
	print_paths_only := false
	json_output := false
	watch := false
	generated_dir := ""
	input := ""

    i := 2
    for i < len(os.args) {
        switch os.args[i] {
        case "--reload":
            reload_mode = true
            i += 1
		case "--rebuild":
			rebuild_only = true
			i += 1
		case "--watch":
			watch = true
			i += 1
		case "--print-paths":
			print_paths_only = true
			i += 1
        case "--json":
            json_output = true
            i += 1
        case "--generated-dir":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            generated_dir = os.args[i+1]
            i += 2
        case:
            if input == "" {
                input = os.args[i]
                i += 1
            } else {
                print_usage()
                os.exit(2)
            }
        }
    }

	if !reload_mode || input == "" {
		print_usage()
		os.exit(2)
	}
	if watch && (rebuild_only || print_paths_only) {
		print_usage()
		os.exit(2)
	}

	reload_app_generate_and_build(input, generated_dir, rebuild_only, print_paths_only, json_output, watch)
}
