package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import kvist "../../src/kvist"

RELOAD_CACHE_DIR :: "reload-apps"

Reload_App_Mode :: enum {
    Step,
    Run,
}

Reload_App_Config :: struct {
    state_type:     string,
    version:        string,
    mode:           Reload_App_Mode,
    step_name:      string,
    run_name:       string,
    init_name:      string,
    on_load_name:   string,
    on_unload_name: string,
    package_name:   string,
    sleep_ms:       int,
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

reload_app_config_from_source :: proc(input, source: string) -> (config: Reload_App_Config, err: kvist.Compile_Error, ok: bool) {
    forms, read_err, read_ok := kvist.read_top_forms(source)
    if !read_ok {
        return config, read_err, false
    }

    config.version = strings.clone("dev")
    config.mode = .Step
    config.sleep_ms = 1000
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
            if len(form.items) != 4 && len(form.items) != 5 {
                return config, kvist.Compile_Error{message = "reload dev mode requires defstate with fields and reload metadata brace forms", span = form.span}, false
            }
            if form.items[1].kind != .Symbol {
                return config, kvist.Compile_Error{message = "defstate expects a symbol name", span = form.items[1].span}, false
            }
            fields_index := 2
            meta_index := 3
            if len(form.items) == 5 {
                if form.items[2].kind != .String {
                    return config, kvist.Compile_Error{message = "defstate docstring must be a string literal", span = form.items[2].span}, false
                }
                fields_index = 3
                meta_index = 4
            }
            if form.items[fields_index].kind != .Brace {
                return config, kvist.Compile_Error{message = "defstate fields must be a brace form", span = form.items[fields_index].span}, false
            }
            if form.items[meta_index].kind != .Brace {
                return config, kvist.Compile_Error{message = "defstate reload metadata must be a brace form", span = form.items[meta_index].span}, false
            }
            found_defstate = true
            config.state_type = strings.clone(kvist.map_name(form.items[1].text))
            meta := form.items[meta_index]
            i := 0
            for i < len(meta.items) {
                if i+1 >= len(meta.items) {
                return config, kvist.Compile_Error{message = "defstate reload metadata has a missing value", span = meta.span}, false
            }
            key_form := meta.items[i]
            value := meta.items[i+1]
            if key_form.kind != .Keyword || len(key_form.text) < 2 {
                return config, kvist.Compile_Error{message = "defstate reload metadata expects keyword keys", span = key_form.span}, false
            }
                key := key_form.text[1:]
                switch key {
                case "step":
                    if value.kind != .Symbol {
                        return config, kvist.Compile_Error{message = "defstate :step must be a symbol", span = value.span}, false
                    }
                    if config.run_name != "" {
                        return config, kvist.Compile_Error{message = "defstate reload metadata cannot specify both :step and :run", span = value.span}, false
                    }
                    if config.step_name != "" {
                        delete(config.step_name)
                    }
                    config.mode = .Step
                    config.step_name = strings.clone(kvist.map_name(value.text))
                case "run":
                    if value.kind != .Symbol {
                        return config, kvist.Compile_Error{message = "defstate :run must be a symbol", span = value.span}, false
                    }
                    if config.step_name != "" {
                        return config, kvist.Compile_Error{message = "defstate reload metadata cannot specify both :step and :run", span = value.span}, false
                    }
                    if config.run_name != "" {
                        delete(config.run_name)
                    }
                    config.mode = .Run
                    config.run_name = strings.clone(kvist.map_name(value.text))
                case "init":
                    if value.kind == .Nil {
                        config.init_name = ""
                    } else {
                        if value.kind != .Symbol {
                            return config, kvist.Compile_Error{message = "defstate :init must be a symbol or nil", span = value.span}, false
                        }
                        if config.init_name != "" {
                            delete(config.init_name)
                        }
                        config.init_name = strings.clone(kvist.map_name(value.text))
                    }
                case "on-load":
                    if value.kind == .Nil {
                        config.on_load_name = ""
                    } else {
                        if value.kind != .Symbol {
                            return config, kvist.Compile_Error{message = "defstate :on-load must be a symbol or nil", span = value.span}, false
                        }
                        if config.on_load_name != "" {
                            delete(config.on_load_name)
                        }
                        config.on_load_name = strings.clone(kvist.map_name(value.text))
                    }
                case "on-unload":
                    if value.kind == .Nil {
                        config.on_unload_name = ""
                    } else {
                        if value.kind != .Symbol {
                            return config, kvist.Compile_Error{message = "defstate :on-unload must be a symbol or nil", span = value.span}, false
                        }
                        if config.on_unload_name != "" {
                            delete(config.on_unload_name)
                        }
                        config.on_unload_name = strings.clone(kvist.map_name(value.text))
                    }
                case "version":
                    if value.kind != .String {
                        return config, kvist.Compile_Error{message = "defstate :version must be a string", span = value.span}, false
                    }
                    if config.version != "" {
                        delete(config.version)
                    }
                    config.version = kvist.unquote_string(value.text)
                case "sleep-ms":
                    if value.kind != .Number {
                        return config, kvist.Compile_Error{message = "defstate :sleep-ms must be an integer", span = value.span}, false
                    }
                    parsed, parsed_ok := strconv.parse_int(value.text)
                    if !parsed_ok || parsed < 1 {
                        return config, kvist.Compile_Error{message = "defstate :sleep-ms must be a positive integer", span = value.span}, false
                    }
                    config.sleep_ms = parsed
                case:
                    return config, kvist.Compile_Error{message = fmt.tprintf("unsupported defstate reload metadata option: :%s", key), span = key_form.span}, false
                }
                i += 2
            }
        }
    }

    if !found_defstate {
        return config, kvist.Compile_Error{message = "missing defstate declaration"}, false
    }
    if config.step_name == "" && config.run_name == "" {
        return config, kvist.Compile_Error{message = "defstate reload metadata requires :step or :run"}, false
    }
    if config.package_name == "" {
        config.package_name = strings.clone("main")
    }
    return config, kvist.Compile_Error{}, true
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

reload_app_module_source :: proc(config: Reload_App_Config, app_import_path, kvist_hot_import_path: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "package hot_app_module\n\n")
    strings.write_string(&builder, "import \"base:runtime\"\n")
    fmt.sbprintf(&builder, "import app %q\n", app_import_path)
    fmt.sbprintf(&builder, "import kvist_hot %q\n\n", kvist_hot_import_path)
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "kvist_hot_api_version: u32 = 1\n\n")
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "kvist_hot_state_size :: proc \"c\" () -> int {\n    return size_of(app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, ")\n}\n\n")
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "kvist_hot_state_align :: proc \"c\" () -> int {\n    return align_of(app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, ")\n}\n\n")
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "kvist_hot_on_load :: proc \"c\" (state: rawptr, is_reload: bool) {\n    context = runtime.default_context()\n    app_state := (^app.")
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
    strings.write_string(&builder, "kvist_hot_on_unload :: proc \"c\" (state: rawptr) {\n    context = runtime.default_context()\n    app_state := (^app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, ")(state)\n")
    if config.on_unload_name != "" {
        strings.write_string(&builder, "    app.")
        strings.write_string(&builder, config.on_unload_name)
        strings.write_string(&builder, "(app_state)\n")
    }
    strings.write_string(&builder, "}\n\n")
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "kvist_hot_app_version :: proc \"c\" () -> cstring {\n    return cstring(")
    fmt.sbprintf(&builder, "%q", config.version)
    strings.write_string(&builder, ")\n}\n\n")
    strings.write_string(&builder, "@(export)\n")
    switch config.mode {
    case .Step:
        strings.write_string(&builder, "kvist_hot_app_step :: proc \"c\" (state: rawptr) {\n    context = runtime.default_context()\n    app_state := (^app.")
        strings.write_string(&builder, config.state_type)
        strings.write_string(&builder, ")(state)\n    app.")
        strings.write_string(&builder, config.step_name)
        strings.write_string(&builder, "(app_state)\n}\n")
    case .Run:
        strings.write_string(&builder, "kvist_hot_app_run :: proc \"c\" (state: rawptr, host: rawptr) {\n    context = runtime.default_context()\n    app_state := (^app.")
        strings.write_string(&builder, config.state_type)
        strings.write_string(&builder, ")(state)\n    app_host := (^app.reload__Run_Host")
        strings.write_string(&builder, ")(host)\n    app.")
        strings.write_string(&builder, config.run_name)
        strings.write_string(&builder, "(app_state, app_host)\n}\n")
    }

    return strings.clone(strings.to_string(builder))
}

reload_app_host_source :: proc(config: Reload_App_Config, input_path, app_import_path, kvist_hot_import_path, hot_app_runtime_import_path, module_binary_path: string, json_output := false) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "package hot_app_host\n\n")
    strings.write_string(&builder, "import \"core:dynlib\"\n")
    strings.write_string(&builder, "import \"core:fmt\"\n")
    strings.write_string(&builder, "import \"core:os\"\n")
    if json_output {
        strings.write_string(&builder, "import \"core:strings\"\n")
    }
    strings.write_string(&builder, "import \"core:time\"\n")
    fmt.sbprintf(&builder, "import app %q\n", app_import_path)
    fmt.sbprintf(&builder, "import kvist_hot %q\n\n", kvist_hot_import_path)
    if config.mode == .Run {
        fmt.sbprintf(&builder, "import reload_runtime %q\n\n", hot_app_runtime_import_path)
    }

    strings.write_string(&builder, "App_Symbols :: struct {\n")
    strings.write_string(&builder, "    api_version: ^u32 `dynlib:\"kvist_hot_api_version\"`,\n")
    strings.write_string(&builder, "    state_size:  proc \"c\" () -> int `dynlib:\"kvist_hot_state_size\"`,\n")
    strings.write_string(&builder, "    state_align: proc \"c\" () -> int `dynlib:\"kvist_hot_state_align\"`,\n")
    strings.write_string(&builder, "    on_load:     proc \"c\" (state: rawptr, is_reload: bool) `dynlib:\"kvist_hot_on_load\"`,\n")
    strings.write_string(&builder, "    on_unload:   proc \"c\" (state: rawptr) `dynlib:\"kvist_hot_on_unload\"`,\n")
    strings.write_string(&builder, "    version:     proc \"c\" () -> cstring `dynlib:\"kvist_hot_app_version\"`,\n")
    switch config.mode {
    case .Step:
        strings.write_string(&builder, "    step:        proc \"c\" (state: rawptr) `dynlib:\"kvist_hot_app_step\"`,\n")
    case .Run:
        strings.write_string(&builder, "    run:         proc \"c\" (state: rawptr, host: rawptr) `dynlib:\"kvist_hot_app_run\"`,\n")
    }
    strings.write_string(&builder, "    __handle:    dynlib.Library,\n")
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
        strings.write_string(&builder, "reload_emit_event :: proc(event, input_path, package_name, module_binary_path, rebuild_command, version, message: string, generation: int) {\n")
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
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"version\")\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \": \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, version)\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \", \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"message\")\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \": \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, message)\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \"}\\n\")\n")
        strings.write_string(&builder, "    fmt.print(reload_event_prefix, strings.to_string(payload))\n")
        strings.write_string(&builder, "}\n\n")
    }
    strings.write_string(&builder, "main :: proc() {\n")
    fmt.sbprintf(&builder, "    module_path := %q\n", module_binary_path)
    fmt.sbprintf(&builder, "    rebuild_command := %q\n", fmt.tprintf("kvist dev --reload %q --rebuild", input_path))
    if config.mode == .Step {
        fmt.sbprintf(&builder, "    sleep_duration := time.Duration(%d) * time.Millisecond\n", config.sleep_ms)
    }
    strings.write_string(&builder, "    state := app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, "{}\n")
    strings.write_string(&builder, "    symbols := App_Symbols{}\n\n")
    strings.write_string(&builder, "    reloader, reloader_err, reloader_ok := kvist_hot.new_reloader(module_path)\n")
    strings.write_string(&builder, "    if !reloader_ok {\n        fmt.eprintln(reloader_err)\n        os.exit(1)\n    }\n")
    strings.write_string(&builder, "    defer {\n        if reloader.has_loaded {\n            kvist_hot.unload_current_module(&symbols, &state)\n        }\n    }\n\n")
    strings.write_string(&builder, "    initial_err, initial_ok := kvist_hot.load_initial_module(&reloader, &symbols, &state)\n")
    strings.write_string(&builder, "    if !initial_ok {\n        fmt.eprintln(initial_err)\n        os.exit(1)\n    }\n\n")
    if json_output {
        fmt.sbprintf(&builder, "    reload_emit_event(\"started\", %q, %q, module_path, rebuild_command, string(symbols.version()), \"reload session started\", reloader.generation)\n", input_path, config.package_name)
    } else {
        fmt.sbprintf(&builder, "    fmt.println(\"[reload] running %s\")\n", config.package_name)
        fmt.sbprintf(&builder, "    fmt.println(%q)\n", fmt.tprintf("[reload] rebuild with: kvist dev --reload %q --rebuild", input_path))
    }
    switch config.mode {
    case .Step:
        strings.write_string(&builder, "    for {\n")
        strings.write_string(&builder, "        symbols.step(rawptr(&state))\n")
        if json_output {
            strings.write_string(&builder, "        // Structured events are emitted only on start and successful/failed reloads.\n")
        } else {
            strings.write_string(&builder, "        fmt.printf(\"[reload] generation=%d version=%s\\n\", reloader.generation, string(symbols.version()))\n")
        }
        strings.write_string(&builder, "        changed, reload_err, reload_ok := kvist_hot.reload_module_if_source_changed(&reloader, &symbols, &state)\n")
        if json_output {
            strings.write_string(&builder, "        if changed && !reload_ok {\n            reload_emit_event(\"reload_failed\", ")
            fmt.sbprintf(&builder, "%q, %q", input_path, config.package_name)
            strings.write_string(&builder, ", module_path, rebuild_command, string(symbols.version()), reload_err, reloader.generation)\n            fmt.eprintln(reload_err)\n        }\n")
            strings.write_string(&builder, "        if changed && reload_ok {\n            reload_emit_event(\"reloaded\", ")
            fmt.sbprintf(&builder, "%q, %q", input_path, config.package_name)
            strings.write_string(&builder, ", module_path, rebuild_command, string(symbols.version()), \"reload applied\", reloader.generation)\n        }\n")
        } else {
            strings.write_string(&builder, "        if changed && !reload_ok {\n            fmt.eprintln(reload_err)\n        }\n")
        }
        strings.write_string(&builder, "        time.sleep(sleep_duration)\n")
        strings.write_string(&builder, "    }\n")
    case .Run:
        strings.write_string(&builder, "    host := reload_runtime.run_host_init(&reloader)\n")
        strings.write_string(&builder, "    for {\n")
        strings.write_string(&builder, "        reload_runtime.run_host_begin_cycle(&host)\n")
        if !json_output {
            strings.write_string(&builder, "        fmt.printf(\"[reload] generation=%d version=%s\\n\", reloader.generation, string(symbols.version()))\n")
        }
        strings.write_string(&builder, "        symbols.run(rawptr(&state), rawptr(&host))\n")
        if json_output {
            strings.write_string(&builder, "        if host.checkpoint_error != \"\" {\n            reload_emit_event(\"checkpoint_error\", ")
            fmt.sbprintf(&builder, "%q, %q", input_path, config.package_name)
            strings.write_string(&builder, ", module_path, rebuild_command, string(symbols.version()), host.checkpoint_error, reloader.generation)\n            fmt.eprintln(host.checkpoint_error)\n            os.exit(1)\n        }\n")
        } else {
            strings.write_string(&builder, "        if host.checkpoint_error != \"\" {\n            fmt.eprintln(host.checkpoint_error)\n            os.exit(1)\n        }\n")
        }
        strings.write_string(&builder, "        if host.reload_requested {\n")
        strings.write_string(&builder, "            changed, reload_err, reload_ok := kvist_hot.reload_module_if_source_changed(&reloader, &symbols, &state)\n")
        if json_output {
            strings.write_string(&builder, "            if !reload_ok {\n                reload_emit_event(\"reload_failed\", ")
            fmt.sbprintf(&builder, "%q, %q", input_path, config.package_name)
            strings.write_string(&builder, ", module_path, rebuild_command, string(symbols.version()), reload_err, reloader.generation)\n                fmt.eprintln(reload_err)\n                os.exit(1)\n            }\n")
            strings.write_string(&builder, "            if changed {\n                reload_emit_event(\"reloaded\", ")
            fmt.sbprintf(&builder, "%q, %q", input_path, config.package_name)
            strings.write_string(&builder, ", module_path, rebuild_command, string(symbols.version()), \"reload applied\", reloader.generation)\n                continue\n            }\n")
        } else {
            strings.write_string(&builder, "            if !reload_ok {\n                fmt.eprintln(reload_err)\n                os.exit(1)\n            }\n")
            strings.write_string(&builder, "            if changed {\n                continue\n            }\n")
        }
        strings.write_string(&builder, "        }\n")
        strings.write_string(&builder, "        break\n")
        strings.write_string(&builder, "    }\n")
    }
    strings.write_string(&builder, "}\n")

    return strings.clone(strings.to_string(builder))
}

reload_app_main_source :: proc(config: Reload_App_Config, app_import_path, reload_runtime_import_path: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "package reload_app_main\n\n")
    if config.mode == .Step {
        strings.write_string(&builder, "import \"core:time\"\n")
    }
    fmt.sbprintf(&builder, "import app %q\n", app_import_path)
    if config.mode == .Run {
        fmt.sbprintf(&builder, "import reload_runtime %q\n", reload_runtime_import_path)
    }
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
    switch config.mode {
    case .Step:
        fmt.sbprintf(&builder, "    sleep_duration := time.Duration(%d) * time.Millisecond\n", config.sleep_ms)
        strings.write_string(&builder, "    for {\n")
        strings.write_string(&builder, "        app.")
        strings.write_string(&builder, config.step_name)
        strings.write_string(&builder, "(&state)\n")
        strings.write_string(&builder, "        time.sleep(sleep_duration)\n")
        strings.write_string(&builder, "    }\n")
    case .Run:
        strings.write_string(&builder, "    host := reload_runtime.run_host_init(nil)\n")
        strings.write_string(&builder, "    app.")
        strings.write_string(&builder, config.run_name)
        strings.write_string(&builder, "(&state, &host)\n")
    }
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

    kvist_hot_path, hot_join_err := os.join_path({repo_root, "src", "kvist_hot"}, context.allocator)
    if hot_join_err != nil {
        fmt.eprintln("failed to build kvist_hot import path")
        os.exit(1)
    }
    defer delete(kvist_hot_path)
    reload_runtime_path, reload_runtime_err := os.join_path({repo_root, "src", "kvist_hot_app_runtime"}, context.allocator)
    if reload_runtime_err != nil {
        fmt.eprintln("failed to build kvist_hot_app_runtime import path")
        os.exit(1)
    }
    defer delete(reload_runtime_path)

    module_app_import := reload_app_relative_path_or_exit(paths.module_dir, paths.app_dir)
    defer delete(module_app_import)
    module_hot_import := reload_app_relative_path_or_exit(paths.module_dir, kvist_hot_path)
    defer delete(module_hot_import)
    host_app_import := reload_app_relative_path_or_exit(paths.host_dir, paths.app_dir)
    defer delete(host_app_import)
    host_hot_import := reload_app_relative_path_or_exit(paths.host_dir, kvist_hot_path)
    defer delete(host_hot_import)
    host_reload_runtime_import := reload_app_relative_path_or_exit(paths.host_dir, reload_runtime_path)
    defer delete(host_reload_runtime_import)
    module_source := reload_app_module_source(config, module_app_import, module_hot_import)
    defer delete(module_source)
    host_source := reload_app_host_source(config, input_abs, host_app_import, host_hot_import, host_reload_runtime_import, paths.module_binary, json_output)
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

reload_app_generate_and_build :: proc(input: string, generated_dir := "", rebuild_only, print_paths_only, json_output: bool) {
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

    root_abs := reload_app_absolute_path_or_exit(root_dir)
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

    module_build_exit_code := build_odin_package(paths.module_dir, paths.module_binary, "-build-mode:dll")
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

    root_abs := reload_app_absolute_path_or_exit(root_dir)
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

    reload_runtime_path, runtime_join_err := os.join_path({repo_root, "src", "kvist_hot_app_runtime"}, context.allocator)
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
    _, ok := reload_app_primary_input(input)
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

    reload_app_generate_and_build(input, generated_dir, rebuild_only, print_paths_only, json_output)
}
