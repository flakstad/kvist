// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import kvist "../../odin/kvist"

CACHE_DIR :: ".kvist-cache"
COMPILE_CACHE_VERSION :: "kvist-compile-cache-v7"

ownership_audit_enabled: bool
explain_cache_enabled: bool

print_usage :: proc() {
    fmt.println("usage:")
    fmt.println("  kvist <input.kvist> [-o output.odin] [--map output.map] [--eval form] [--no-print] [--timings] [--timings-json path]")
    fmt.println("  kvist compile <input.kvist> [-o output.odin] [--map output.map] [--packages] [--ownership-audit] [--timings] [--timings-json path]")
    fmt.println("  kvist dev --reload <input.kvist> [--rebuild] [--watch] [--generated-dir dir] [--print-paths] [--json]")
    fmt.println("  kvist build <input.kvist> [--out output-binary] [--generated output.odin] [--reload] [--generated-dir dir] [--ownership-audit] [--explain-cache] [--timings] [--timings-json path]")
    fmt.println("  kvist check <input.kvist> [--generated output.odin] [--reload] [--generated-dir dir] [--ownership-audit] [--explain-cache] [--timings] [--timings-json path]")
    fmt.println("  kvist frontend-check <input.kvist> [--ownership-audit] [--explain-cache] [--timings] [--timings-json path]")
    fmt.println("  kvist run <input.kvist> [--generated output.odin] [--reload] [--generated-dir dir] [--ownership-audit] [--explain-cache] [--timings] [--timings-json path]")
    fmt.println("  kvist test <input.kvist> [--generated output.odin] [--names test1,test2] [--track-memory] [--ownership-audit] [--explain-cache] [--timings] [--timings-json path]")
    fmt.println("  kvist eval <input.kvist> <form> [--no-print] [--check] [--generated output.odin] [--save name] [--ownership-audit] [--timings] [--timings-json path]")
    fmt.println("  kvist repl <input.kvist> [--protocol jsonl]")
    fmt.println("  kvist repl --attach <endpoint-dir> --protocol jsonl")
    fmt.println("  kvist repl <input.kvist> --attach <endpoint-dir> --protocol jsonl")
    fmt.println("  kvist nrepl <context.kvist> [--port PORT] [--port-file PATH] [--no-port-file]")
    fmt.println("  kvist expand <input.kvist> <form> [--no-print] [-o output.odin]")
    fmt.println("  kvist macroexpand <input.kvist> <form> [-o output.kvist] [--map output.map]")
    fmt.println("  kvist symbols <input.kvist>")
    fmt.println("  kvist lifetimes <input.kvist>")
    fmt.println("  kvist editor-symbols <input.kvist> [identifier]")
    fmt.println("  kvist lookup <input.kvist> <identifier>")
    fmt.println("  kvist complete <input.kvist> [prefix]")
    fmt.println("  kvist doc <input.kvist> <identifier>")
    fmt.println("  kvist xref <input.kvist> <identifier>")
    fmt.println("  kvist builtin-symbols")
    fmt.println("  kvist imported-symbols <input.kvist>")
    fmt.println("  kvist package-symbols <import-path> [alias]")
    fmt.println("  kvist root")
    fmt.println("  kvist cache path <name>")
    fmt.println("  kvist cache list")
    fmt.println("  kvist cache rm <name>")
    fmt.println("  kvist cache inspect")
    fmt.println("  kvist cache clear [input.kvist]")
}

is_help_arg :: proc(text: string) -> bool {
    return text == "help" || text == "--help" || text == "-h"
}

is_command :: proc(text: string) -> bool {
    return is_help_arg(text) || text == "compile" || text == "dev" || text == "build" || text == "check" || text == "frontend-check" || text == "run" || text == "test" || text == "eval" || text == "repl" || text == "nrepl" || text == "__repl-worker" || text == "expand" || text == "macroexpand" || text == "symbols" || text == "lifetimes" || text == "editor-symbols" || text == "lookup" || text == "complete" || text == "doc" || text == "xref" || text == "builtin-symbols" || text == "imported-symbols" || text == "package-symbols" || text == "root" || text == "cache"
}

root_command :: proc() {
    if len(os.args) != 2 {
        fmt.eprintln("usage: kvist root")
        exit_with_timing(2)
    }
    roots := kvist.kvist_source_package_roots()
    defer kvist.delete_string_slice(&roots)
    if len(roots) == 0 {
        fmt.eprintln("could not resolve Kvist package root")
        exit_with_timing(1)
    }
    fmt.println(roots[0])
}

parse_legacy_compile :: proc() {
    input := os.args[1]
    output_path := ""
    map_path := ""
    eval_source := ""
    no_print := false

    i := 2
    for i < len(os.args) {
        switch os.args[i] {
        case "-o":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--map":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            map_path = os.args[i+1]
            i += 2
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--eval":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            eval_source = os.args[i+1]
            i += 2
        case "--no-print":
            no_print = true
            i += 1
        case:
            if parse_timing_arg(&i) {
                continue
            }
            print_usage()
            exit_with_timing(2)
        }
    }

    timing_begin("eval" if eval_source != "" else "compile", input)
    if eval_source != "" {
        if map_path != "" {
            fmt.eprintln("--map cannot be used with --eval")
            exit_with_timing(2)
        }
        compile_eval_emit_command(input, eval_source, output_path, no_print)
        return
    }
    compile_file_command(input, output_path, map_path)
}

parse_compile_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }
    input := os.args[2]
    output_path := ""
    map_path := ""
    package_output := false

    i := 3
    for i < len(os.args) {
        switch os.args[i] {
        case "-o":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--map":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            map_path = os.args[i+1]
            i += 2
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--packages":
            package_output = true
            i += 1
        case:
            if parse_timing_arg(&i) {
                continue
            }
            print_usage()
            exit_with_timing(2)
        }
    }

    timing_begin("compile", input)
    if package_output {
        compile_package_file_command(input, output_path, map_path)
    } else {
        compile_file_command(input, output_path, map_path)
    }
}

parse_run_or_check_command :: proc(odin_command: string) {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }
    input := ""
    generated_path := ""
    generated_dir := ""
    binary_output_path := ""
    reload_mode := false

    i := 2
    for i < len(os.args) {
        switch os.args[i] {
        case "--reload":
            reload_mode = true
            i += 1
        case "--generated":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            generated_path = os.args[i+1]
            i += 2
        case "--generated-dir":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            generated_dir = os.args[i+1]
            i += 2
        case "--out":
            if odin_command != "build" || i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            binary_output_path = os.args[i+1]
            i += 2
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--explain-cache":
            explain_cache_enabled = true
            i += 1
        case:
            if parse_timing_arg(&i) {
                continue
            }
            if input == "" {
                input = os.args[i]
                i += 1
            } else {
                print_usage()
                exit_with_timing(2)
            }
        }
    }

    if input == "" {
        print_usage()
        exit_with_timing(2)
    }

    timing_begin(odin_command, input)
    if reload_mode {
        if timings_enabled() {
            fmt.eprintln("timings are not supported with reload mode")
            exit_with_timing(2)
        }
        if generated_path != "" || binary_output_path != "" {
            print_usage()
            exit_with_timing(2)
        }
        exit_with_timing(reload_app_generate_and_execute(input, odin_command, generated_dir))
    }

    if generated_path == "" && source_declares_reload_app(input) {
        if timings_enabled() {
            fmt.eprintln("timings are not supported with reload applications")
            exit_with_timing(2)
        }
        if binary_output_path != "" {
            print_usage()
            exit_with_timing(2)
        }
        exit_with_timing(reload_app_generate_and_execute(input, odin_command, generated_dir))
    }

    exit_with_timing(run_generated_command(input, generated_path, odin_command, binary_output_path))
}

parse_frontend_check_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }
    input := os.args[2]
    i := 3
    for i < len(os.args) {
        switch os.args[i] {
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--explain-cache":
            explain_cache_enabled = true
            i += 1
        case:
            if parse_timing_arg(&i) {
                continue
            }
            print_usage()
            exit_with_timing(2)
        }
    }
    timing_begin("frontend-check", input)
    exit_with_timing(frontend_check_command(input))
}

parse_test_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }
    input := os.args[2]
    generated_path := ""
    test_names := ""
    track_memory := false

    i := 3
    for i < len(os.args) {
        switch os.args[i] {
        case "--generated":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            generated_path = os.args[i+1]
            i += 2
        case "--names":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            test_names = os.args[i+1]
            i += 2
        case "--track-memory":
            track_memory = true
            i += 1
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--explain-cache":
            explain_cache_enabled = true
            i += 1
        case:
            if parse_timing_arg(&i) {
                continue
            }
            print_usage()
            exit_with_timing(2)
        }
    }

    timing_begin("test", input)
    exit_with_timing(test_command(input, generated_path, test_names, track_memory))
}

parse_eval_command :: proc() {
    if len(os.args) < 4 {
        print_usage()
        exit_with_timing(2)
    }
    input := os.args[2]
    eval_source := os.args[3]
    generated_path := ""
    save_name := ""
    no_print := false
    check_only := false

    i := 4
    for i < len(os.args) {
        switch os.args[i] {
        case "--generated":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            generated_path = os.args[i+1]
            i += 2
        case "--no-print":
            no_print = true
            i += 1
        case "--check":
            check_only = true
            i += 1
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--save":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            save_name = os.args[i+1]
            i += 2
        case:
            if parse_timing_arg(&i) {
                continue
            }
            print_usage()
            exit_with_timing(2)
        }
    }

    timing_begin("eval", input)
    exit_with_timing(eval_command(input, eval_source, generated_path, save_name, no_print, check_only))
}

parse_expand_command :: proc() {
    if len(os.args) < 4 {
        print_usage()
        exit_with_timing(2)
    }
    input := os.args[2]
    eval_source := os.args[3]
    output_path := ""
    no_print := false

    i := 4
    for i < len(os.args) {
        switch os.args[i] {
        case "-o":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--no-print":
            no_print = true
            i += 1
        case:
            print_usage()
            exit_with_timing(2)
        }
    }

    compile_eval_emit_command(input, eval_source, output_path, no_print)
}

parse_macroexpand_command :: proc() {
    if len(os.args) < 4 {
        print_usage()
        exit_with_timing(2)
    }
    input := os.args[2]
    eval_source := os.args[3]
    output_path := ""
    map_path := ""

    i := 4
    for i < len(os.args) {
        switch os.args[i] {
        case "-o":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--map":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            map_path = os.args[i+1]
            i += 2
        case:
            print_usage()
            exit_with_timing(2)
        }
    }

    macroexpand_command(input, eval_source, output_path, map_path)
}

parse_symbols_command :: proc() {
    if len(os.args) != 3 {
        print_usage()
        exit_with_timing(2)
    }
    symbols_command(os.args[2])
}

parse_lifetimes_command :: proc() {
    if len(os.args) != 3 {
        print_usage()
        exit_with_timing(2)
    }
    lifetimes_command(os.args[2])
}

parse_editor_symbols_command :: proc() {
    if len(os.args) != 3 && len(os.args) != 4 {
        print_usage()
        exit_with_timing(2)
    }
    identifier := ""
    if len(os.args) == 4 {
        identifier = os.args[3]
    }
    editor_symbols_command(os.args[2], identifier)
}

parse_lookup_command :: proc() {
    if len(os.args) != 4 {
        print_usage()
        exit_with_timing(2)
    }
    lookup_command(os.args[2], os.args[3])
}

parse_complete_command :: proc() {
    if len(os.args) != 3 && len(os.args) != 4 {
        print_usage()
        exit_with_timing(2)
    }
    prefix := ""
    if len(os.args) == 4 {
        prefix = os.args[3]
    }
    complete_command(os.args[2], prefix)
}

parse_doc_command :: proc() {
    if len(os.args) != 4 {
        print_usage()
        exit_with_timing(2)
    }
    doc_command(os.args[2], os.args[3])
}

parse_xref_command :: proc() {
    if len(os.args) != 4 {
        print_usage()
        exit_with_timing(2)
    }
    xref_command(os.args[2], os.args[3])
}

parse_builtin_symbols_command :: proc() {
    if len(os.args) != 2 {
        print_usage()
        exit_with_timing(2)
    }
    builtin_symbols_command()
}

parse_imported_symbols_command :: proc() {
    if len(os.args) != 3 {
        print_usage()
        exit_with_timing(2)
    }
    imported_symbols_command(os.args[2])
}

parse_package_symbols_command :: proc() {
    if len(os.args) != 3 && len(os.args) != 4 {
        print_usage()
        exit_with_timing(2)
    }
    alias := ""
    if len(os.args) == 4 {
        alias = os.args[3]
    }
    package_symbols_command(os.args[2], alias)
}

main :: proc() {
    if len(os.args) < 2 {
        print_usage()
        exit_with_timing(2)
    }

    if !is_command(os.args[1]) {
        parse_legacy_compile()
        return
    }

    switch os.args[1] {
    case "help", "--help", "-h":
        print_usage()
    case "compile":
        parse_compile_command()
    case "dev":
        parse_dev_command()
    case "build":
        parse_run_or_check_command("build")
    case "check":
        parse_run_or_check_command("check")
    case "frontend-check":
        parse_frontend_check_command()
    case "run":
        parse_run_or_check_command("run")
    case "test":
        parse_test_command()
    case "eval":
        parse_eval_command()
    case "repl":
        parse_repl_command()
    case "nrepl":
        parse_nrepl_command()
    case "__repl-worker":
        os.exit(repl_worker_command())
    case "expand":
        parse_expand_command()
    case "macroexpand":
        parse_macroexpand_command()
    case "symbols":
        parse_symbols_command()
    case "lifetimes":
        parse_lifetimes_command()
    case "editor-symbols":
        parse_editor_symbols_command()
    case "lookup":
        parse_lookup_command()
    case "complete":
        parse_complete_command()
    case "doc":
        parse_doc_command()
    case "xref":
        parse_xref_command()
    case "builtin-symbols":
        parse_builtin_symbols_command()
    case "imported-symbols":
        parse_imported_symbols_command()
    case "package-symbols":
        parse_package_symbols_command()
    case "root":
        root_command()
    case "cache":
        cache_command()
    }
    final_status := timing_finish(0)
    if final_status != 0 {
        os.exit(final_status)
    }
}
