// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
odin_symbol_visible_to_tooling_filters_internal_noise :: proc(t: ^testing.T) {
    testing.expect_value(t, kvist.odin_symbol_visible_to_tooling("/tmp/fmt/fmt_os.odin", "println"), true)
    testing.expect_value(t, kvist.odin_symbol_visible_to_tooling("/tmp/fmt/fmt.odin", "fmt_arg"), false)
    testing.expect_value(t, kvist.odin_symbol_visible_to_tooling("/tmp/fmt/example.odin", "SomeType"), false)
    testing.expect_value(t, kvist.odin_symbol_visible_to_tooling("/tmp/fmt/fmt_js.odin", "stderr"), false)
    testing.expect_value(t, kvist.odin_symbol_visible_to_tooling("/tmp/fmt/fmt_os.odin", "main"), false)
}

@(test)
compile_duplicate_plain_raw_declarations_emit_once :: proc(t: ^testing.T) {
    source := `(package main)
(odin "Shared_Raw_Handle :: distinct rawptr")
(odin "Shared_Raw_Handle :: distinct rawptr")

(defn use-handle [handle: Shared_Raw_Handle] -> Shared_Raw_Handle
  handle)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, count_substring(output, "Shared_Raw_Handle :: distinct rawptr"), 1)
    testing.expect_value(t, strings.contains(output, "use_handle :: proc(handle: Shared_Raw_Handle) -> Shared_Raw_Handle"), true)
}
