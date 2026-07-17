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
