package main

import "core:os"
import "core:testing"

@(test)
compile_cache_distinguishes_entry_files_in_same_package :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-cache-entry-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    first_path, first_path_err := os.join_path({dir, "first.kvist"}, context.allocator)
    second_path, second_path_err := os.join_path({dir, "second.kvist"}, context.allocator)
    testing.expect_value(t, first_path_err == nil, true)
    testing.expect_value(t, second_path_err == nil, true)
    if first_path_err != nil || second_path_err != nil {
        return
    }
    defer delete(first_path)
    defer delete(second_path)

    testing.expect_value(t, os.write_entire_file_from_string(first_path, "(package main)\n(def first 1)\n") == nil, true)
    testing.expect_value(t, os.write_entire_file_from_string(second_path, "(package main)\n(def second 2)\n") == nil, true)

    first_key, first_ok := compile_cache_key(first_path)
    second_key, second_ok := compile_cache_key(second_path)
    testing.expect_value(t, first_ok, true)
    testing.expect_value(t, second_ok, true)
    if first_ok {
        defer delete(first_key)
    }
    if second_ok {
        defer delete(second_key)
    }
    if first_ok && second_ok {
        testing.expect_value(t, first_key != second_key, true)
    }
}

@(test)
odin_timing_csv_is_normalized :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-timing-csv-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)
    path, path_err := os.join_path({dir, "timings.csv"}, context.allocator)
    testing.expect_value(t, path_err == nil, true)
    if path_err != nil {
        return
    }
    defer delete(path)
    source := `"Total Time", 120
"initialization", 2
"parse files", 20
"type check", 40
"LLVM API Code Gen ( 4 modules )", 50
"lld-link", 5
`
    testing.expect_value(t, os.write_entire_file_from_string(path, source) == nil, true)
    timing_report = {}
    parse_odin_timing_csv(path)
    defer {
        for phase in timing_report.odin.raw {
            delete(phase.name)
        }
        delete(timing_report.odin.raw)
        timing_report = {}
    }
    testing.expect_value(t, timing_report.odin.detail_available, true)
    testing.expect_value(t, timing_report.odin.reported_total_ms, 120.0)
    testing.expect_value(t, timing_report.odin.parse_ms, 20.0)
    testing.expect_value(t, timing_report.odin.type_check_ms, 40.0)
    testing.expect_value(t, timing_report.odin.codegen_ms, 50.0)
    testing.expect_value(t, timing_report.odin.link_ms, 5.0)
    testing.expect_value(t, timing_report.odin.other_ms, 3.0)
}

@(test)
odin_timing_output_filter_preserves_program_output :: proc(t: ^testing.T) {
    output := "\nExporting timings to '/tmp/timings.csv'... Done.\nhello from kvist\n"
    filtered := filter_odin_timing_output(output)
    defer delete(filtered)
    testing.expect_value(t, filtered, "hello from kvist\n")

    diagnostic := "generated.odin(2:3) Error: bad value\nTotal Time - 1.000 ms - 100.00%\n"
    filtered_diagnostic := filter_odin_timing_output(diagnostic)
    defer delete(filtered_diagnostic)
    testing.expect_value(t, filtered_diagnostic, "generated.odin(2:3) Error: bad value\n")
}
