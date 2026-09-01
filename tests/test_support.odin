package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

test_env_mutex: sync.Mutex

repo_temp_test_path :: proc(name: string) -> (string, bool) {
    root, ok_root := kvist.repo_root_for_path(".")
    if !ok_root {
        return "", false
    }
    defer delete(root)
    path, join_err := os.join_path({root, name}, context.allocator)
    if join_err != nil {
        return "", false
    }
    return path, true
}

count_substring :: proc(text, needle: string) -> int {
    if len(needle) == 0 {
        return 0
    }
    count := 0
    offset := 0
    for offset < len(text) {
        idx := strings.index(text[offset:], needle)
        if idx < 0 {
            break
        }
        count += 1
        offset += idx + len(needle)
    }
    return count
}

contains_path :: proc(text, path: string) -> bool {
    windows_path, _ := strings.replace_all(path, "/", "\\", context.temp_allocator)
    escaped_windows_path, _ := strings.replace_all(windows_path, "\\", "\\\\", context.temp_allocator)
    return strings.contains(text, path) ||
           strings.contains(text, windows_path) ||
           strings.contains(text, escaped_windows_path)
}

json_field_contains_path :: proc(text, field, path: string) -> bool {
    escaped_path, _ := strings.replace_all(path, "\\", "\\\\", context.temp_allocator)
    return strings.contains(text, fmt.tprintf(`"%s": "%s"`, field, path)) ||
           strings.contains(text, fmt.tprintf(`"%s": "%s"`, field, escaped_path))
}
