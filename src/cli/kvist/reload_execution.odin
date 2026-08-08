// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import kvist "../../odin/kvist"

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
