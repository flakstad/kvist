package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import kvist "../../odin/kvist"

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

    reload_runtime_path, ok_reload_runtime := reload_runtime_path_from_source_root(input_abs)
    if !ok_reload_runtime {
        fmt.eprintln("failed to locate olive_reload runtime source")
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
