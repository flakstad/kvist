// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import kvist "../../odin/kvist"

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
