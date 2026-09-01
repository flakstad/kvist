package main

import "core:os"
import "core:strings"
import "core:testing"
import kvist "../../odin/kvist"

@(test)
reload_app_config_accepts_typed_version :: proc(t: ^testing.T) {
    source := `(package reload_demo)
(import reload "kvist:reload")
(defstruct App_State {steps: int})
(def Reload_State App_State)
(def Reload_Version: string "v1")
(defn run [state: ^Reload_State host: ^reload.Run_Host]
  (return))`
    config, err, ok :=
        reload_app_config_from_source("reload.kvist", source)
    defer {
        if config.state_type != "" do delete(config.state_type)
        if config.version != "" do delete(config.version)
        if config.reload_prefix != "" do delete(config.reload_prefix)
        if config.run_name != "" do delete(config.run_name)
        if config.init_name != "" do delete(config.init_name)
        if config.on_load_name != "" do delete(config.on_load_name)
        if config.on_unload_name != "" do delete(config.on_unload_name)
        if config.package_name != "" do delete(config.package_name)
    }
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    testing.expect_value(t, config.version, "v1")
    testing.expect_value(t, config.state_type, "Reload_State")
}

@(test)
nrepl_bencode_decodes_requests_and_waits_for_complete_frames :: proc(
    t: ^testing.T,
) {
    encoded :=
        "d4:code7:(+ 1 2)7:contexti0e2:id5:req-14:linei12e2:ns5:kvist" +
        "2:op4:eval7:optionsd5:print4:truee7:session3:s-16:symbol3:prie"
    partial, partial_consumed, partial_status :=
        nrepl_bencode_decode_request(transmute([]byte)encoded[:len(encoded)-1])
    defer nrepl_request_delete(&partial)
    testing.expect_value(t, partial_status, Nrepl_Decode_Status.Incomplete)
    testing.expect_value(t, partial_consumed, 0)

    request, consumed, status :=
        nrepl_bencode_decode_request(transmute([]byte)encoded)
    defer nrepl_request_delete(&request)
    testing.expect_value(t, status, Nrepl_Decode_Status.Complete)
    testing.expect_value(t, consumed, len(encoded))
    testing.expect_value(t, request.op, "eval")
    testing.expect_value(t, request.id, "req-1")
    testing.expect_value(t, request.session, "s-1")
    testing.expect_value(t, request.code, "(+ 1 2)")
    testing.expect_value(t, request.completion_context, "")
    testing.expect_value(t, request.symbol, "pri")
    testing.expect_value(t, request.ns, "kvist")
    testing.expect_value(t, request.has_line, true)
    testing.expect_value(t, request.line, 12)

    cider_encoded := "d7:contextle2:id5:req-24:linele2:op8:completee"
    cider_request, cider_consumed, cider_status :=
        nrepl_bencode_decode_request(transmute([]byte)cider_encoded)
    defer nrepl_request_delete(&cider_request)
    testing.expect_value(t, cider_status, Nrepl_Decode_Status.Complete)
    testing.expect_value(t, cider_consumed, len(cider_encoded))
    testing.expect_value(t, cider_request.completion_context, "")
    testing.expect_value(t, cider_request.has_line, false)
}

@(test)
nrepl_bencode_rejects_non_dictionary_and_malformed_values :: proc(
    t: ^testing.T,
) {
    non_dictionary := "l4:evale"
    request, _, status :=
        nrepl_bencode_decode_request(transmute([]byte)non_dictionary)
    defer nrepl_request_delete(&request)
    testing.expect_value(t, status, Nrepl_Decode_Status.Invalid)

    invalid_length := "d2:op04:evale"
    malformed, _, malformed_status :=
        nrepl_bencode_decode_request(transmute([]byte)invalid_length)
    defer nrepl_request_delete(&malformed)
    testing.expect_value(t, malformed_status, Nrepl_Decode_Status.Invalid)

    invalid_integers := [?]string{
        "d2:id1:x4:linei-0e2:op8:describee",
        "d2:id1:x4:linei+1e2:op8:describee",
    }
    for invalid_integer in invalid_integers {
        invalid_request, _, invalid_status :=
            nrepl_bencode_decode_request(transmute([]byte)invalid_integer)
        nrepl_request_delete(&invalid_request)
        testing.expect_value(t, invalid_status, Nrepl_Decode_Status.Invalid)
    }
}

@(test)
nrepl_bencode_encodes_utf8_strings_and_lists :: proc(t: ^testing.T) {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_bencode_write_string(&builder, "bl\u00e5")
    nrepl_bencode_write_string_list(&builder, {"done", "ok"})
    testing.expect_value(t, strings.to_string(builder), "4:bl\u00e5l4:done2:oke")
}

@(test)
nrepl_file_uri_encodes_paths_for_editor_locations :: proc(t: ^testing.T) {
    uri := nrepl_file_uri("/tmp/Kvist source/#demo.kvist")
    defer delete(uri)
    testing.expect_value(
        t,
        uri,
        "file:///tmp/Kvist%20source/%23demo.kvist",
    )
}

@(test)
nrepl_load_file_preserves_positions_while_skipping_file_only_forms :: proc(
    t: ^testing.T,
) {
    source := `(package demo)
(comment
  (+ 1 2))
(def kept 4)
(defn main [] -> int
  kept)
(+ kept 1)
`
    prepared, message, ok :=
        nrepl_load_file_source(source, "demo.kvist")
    defer delete(prepared)
    defer delete(message)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, len(prepared), len(source))
    testing.expect_value(t, strings.contains(prepared, "package"), false)
    testing.expect_value(t, strings.contains(prepared, "comment"), false)
    testing.expect_value(t, strings.contains(prepared, "defn main"), false)
    testing.expect_value(t, strings.contains(prepared, "(def kept 4)"), true)
    testing.expect_value(t, strings.contains(prepared, "(+ kept 1)"), true)
}

@(test)
nrepl_load_file_reports_reader_errors :: proc(t: ^testing.T) {
    prepared, message, ok :=
        nrepl_load_file_source("(def value 1", "broken.kvist")
    defer delete(prepared)
    defer delete(message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, strings.contains(message, "broken.kvist"), true)
}

@(test)
repl_execution_modes_are_explicit :: proc(t: ^testing.T) {
    cases := [?]struct {
        text: string,
        mode: Repl_Execution_Mode,
    }{
        {"auto", .Auto},
        {"resident", .Resident},
        {"native-adapter", .Native_Adapter},
        {"native-reuse", .Native_Reuse},
        {"native", .Native},
    }
    for item in cases {
        mode, parsed := repl_execution_mode_parse(item.text)
        testing.expect_value(t, parsed, true)
        testing.expect_value(t, mode, item.mode)
        testing.expect_value(t, repl_execution_mode_name(mode), item.text)
    }
    _, parsed := repl_execution_mode_parse("sometimes")
    testing.expect_value(t, parsed, false)
    testing.expect_value(t, repl_execution_mode_allows_plan(.Auto), true)
    testing.expect_value(t, repl_execution_mode_allows_plan(.Native_Adapter), false)
    testing.expect_value(t, repl_execution_mode_allows_adapter(.Native_Adapter), true)
    testing.expect_value(t, repl_execution_mode_allows_adapter(.Native_Reuse), false)
    testing.expect_value(t, repl_execution_mode_allows_loaded_native(.Native_Reuse), true)
    testing.expect_value(t, repl_execution_mode_allows_loaded_native(.Native), false)
}

@(test)
execution_temp_parent_can_follow_source_volume :: proc(t: ^testing.T) {
    colocated := execution_temp_parent(
        "D:/a/kvist/kvist/examples/language/hello.kvist",
        true,
    )
    system_temp := execution_temp_parent(
        "D:/a/kvist/kvist/examples/language/hello.kvist",
        false,
    )
    relative := execution_temp_parent("hello.kvist", true)

    testing.expect_value(
        t,
        colocated,
        "D:/a/kvist/kvist/examples/language",
    )
    testing.expect_value(t, system_temp, "")
    testing.expect_value(t, relative, ".")
}

@(test)
repl_source_line_index_matches_compiler_positions :: proc(t: ^testing.T) {
    source := "alpha\nβeta\n\nlast"
    index := repl_source_line_index(source)
    defer delete(index.starts)
    positions := [?]int{-5, 0, 1, 5, 6, 7, 11, 12, 13, len(source), len(source)+9}
    for position in positions {
        expected_line, expected_column, expected_start, expected_end :=
            kvist.source_position(source, position)
        line, column, line_start, line_end :=
            repl_indexed_source_position(&index, position)
        testing.expect_value(t, line, expected_line)
        testing.expect_value(t, column, expected_column)
        testing.expect_value(t, line_start, expected_start)
        testing.expect_value(t, line_end, expected_end)
    }
}

@(test)
compile_cache_verifies_compiler_content_even_when_metadata_matches :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-compiler-fingerprint-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)
    path, path_err := os.join_path({dir, "compiler"}, context.allocator)
    testing.expect_value(t, path_err == nil, true)
    if path_err != nil {
        return
    }
    defer delete(path)

    testing.expect_value(t, os.write_entire_file_from_string(path, "compiler-a") == nil, true)
    fingerprint, fingerprint_ok := fingerprint_file(path)
    testing.expect_value(t, fingerprint_ok, true)
    if !fingerprint_ok {
        return
    }
    defer delete_dependency_file_fingerprint(&fingerprint)
    testing.expect_value(t, os.write_entire_file_from_string(path, "compiler-b") == nil, true)
    size, modification_time_ns, metadata_ok := file_metadata(path)
    testing.expect_value(t, metadata_ok, true)
    fingerprint.size = size
    fingerprint.modification_time_ns = modification_time_ns
    testing.expect_value(t, file_fingerprint_matches_metadata(fingerprint), true)
    testing.expect_value(t, compiler_fingerprint_matches(fingerprint), false)
}

@(test)
repl_native_artifacts_preserve_file_identity_when_supported :: proc(
    t: ^testing.T,
) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-artifact-link-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    artifact, artifact_err := os.join_path(
        {dir, "artifact.dylib"},
        context.allocator,
    )
    output, output_err := os.join_path(
        {dir, "generation.dylib"},
        context.allocator,
    )
    testing.expect_value(t, artifact_err == nil, true)
    testing.expect_value(t, output_err == nil, true)
    if artifact_err != nil || output_err != nil {
        delete(artifact)
        delete(output)
        return
    }
    defer delete(artifact)
    defer delete(output)

    testing.expect_value(
        t,
        os.write_entire_file_from_string(artifact, "native-image") == nil,
        true,
    )
    testing.expect_value(
        t,
        repl_materialize_native_artifact(output, artifact),
        true,
    )
    artifact_info, artifact_stat_err := os.stat(
        artifact,
        context.allocator,
    )
    output_info, output_stat_err := os.stat(output, context.allocator)
    defer os.file_info_delete(artifact_info, context.allocator)
    defer os.file_info_delete(output_info, context.allocator)
    testing.expect_value(t, artifact_stat_err == nil, true)
    testing.expect_value(t, output_stat_err == nil, true)
    if artifact_stat_err == nil && output_stat_err == nil {
        testing.expect_value(
            t,
            artifact_info.inode == output_info.inode,
            true,
        )
    }

    testing.expect_value(t, os.remove(artifact) == nil, true)
    bytes, read_err := os.read_entire_file_from_path(output, context.allocator)
    defer delete(bytes)
    testing.expect_value(t, read_err == nil, true)
    if read_err == nil {
        testing.expect_value(t, string(bytes), "native-image")
    }
}

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
repl_context_cache_key_tracks_files_and_current_imports :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-context-cache-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)
    support_dir, support_dir_err :=
        os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, support_dir_err == nil, true)
    if support_dir_err != nil {
        return
    }
    defer delete(support_dir)
    testing.expect_value(
        t,
        os.make_directory_all(support_dir) == nil,
        true,
    )
    support_path, support_path_err :=
        os.join_path({support_dir, "support.odin"}, context.allocator)
    testing.expect_value(t, support_path_err == nil, true)
    if support_path_err != nil {
        return
    }
    defer delete(support_path)
    initial_support := `package support

Version :: 1
`
    edited_support := `package support

Version :: 200
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(support_path, initial_support) == nil,
        true,
    )
    context_path, path_err :=
        os.join_path({dir, "context.kvist"}, context.allocator)
    testing.expect_value(t, path_err == nil, true)
    if path_err != nil {
        return
    }
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package context)\n(import support \"support\")\n(defn answer [] -> int 41)\n",
        ) == nil,
        true,
    )
    initial := repl_context_cache_key(context_path, "", "(answer)")
    defer delete(initial)
    with_import := repl_context_cache_key(
        context_path,
        "",
        "(import data \"kvist:data\")",
    )
    defer delete(with_import)
    testing.expect_value(t, initial != "", true)
    testing.expect_value(t, initial != with_import, true)

    initial_plan := kvist.Repl_Execution_Plan{}
    initial_result, initial_err, initial_ok :=
        kvist.compile_eval_path_with_map(
            context_path,
            "(answer)",
            repl_generation = true,
            repl_context_cache_key = initial,
            repl_execution_plan = &initial_plan,
        )
    defer delete(initial_result.output)
    defer kvist.source_map_slice_delete(initial_result.source_map)
    defer kvist.compile_warning_slice_delete(initial_result.warnings)
    defer kvist.compile_error_delete(&initial_err)
    defer kvist.repl_execution_plan_delete(&initial_plan)
    testing.expect_value(t, initial_ok, true)
    // Procedure bodies stay on the native path. A context-cache hit alone
    // must not make the expression planner reinterpret an unloaded call.
    testing.expect_value(t, initial_plan.encoded, "")

    warm_plan := kvist.Repl_Execution_Plan{}
    warm_result, warm_err, warm_ok := kvist.compile_eval_path_with_map(
        context_path,
        "(answer)",
        repl_generation = true,
        repl_context_cache_key = initial,
        repl_execution_plan = &warm_plan,
    )
    defer delete(warm_result.output)
    defer kvist.source_map_slice_delete(warm_result.source_map)
    defer kvist.compile_warning_slice_delete(warm_result.warnings)
    defer kvist.compile_error_delete(&warm_err)
    defer kvist.repl_execution_plan_delete(&warm_plan)
    testing.expect_value(t, warm_ok, true)
    testing.expect_value(t, warm_plan.encoded, "")
    testing.expect_value(t, warm_result.output, initial_result.output)

    testing.expect_value(
        t,
        os.write_entire_file_from_string(support_path, edited_support) == nil,
        true,
    )
    support_edited := repl_context_cache_key(context_path, "", "(answer)")
    defer delete(support_edited)
    testing.expect_value(t, support_edited != initial, true)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(support_path, initial_support) == nil,
        true,
    )
    support_restored := repl_context_cache_key(context_path, "", "(answer)")
    defer delete(support_restored)
    testing.expect_value(t, support_restored, initial)

    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package context)\n(import support \"support\")\n(defn answer [] -> int 4242)\n",
        ) == nil,
        true,
    )
    edited := repl_context_cache_key(context_path, "", "(answer)")
    defer delete(edited)
    testing.expect_value(t, edited != initial, true)

    edited_plan := kvist.Repl_Execution_Plan{}
    edited_result, edited_err, edited_ok := kvist.compile_eval_path_with_map(
        context_path,
        "(answer)",
        repl_generation = true,
        repl_context_cache_key = edited,
        repl_execution_plan = &edited_plan,
    )
    defer delete(edited_result.output)
    defer kvist.source_map_slice_delete(edited_result.source_map)
    defer kvist.compile_warning_slice_delete(edited_result.warnings)
    defer kvist.compile_error_delete(&edited_err)
    defer kvist.repl_execution_plan_delete(&edited_plan)
    testing.expect_value(t, edited_ok, true)
    testing.expect_value(t, edited_plan.encoded, "")
    testing.expect_value(t, edited_result.output != initial_result.output, true)
}

@(test)
repl_thin_generation_keeps_only_native_dependency_closure :: proc(t: ^testing.T) {
    source := `package main

import fmt "core:fmt"
import runtime "base:runtime"

@(export)
kvist_repl_api_version: u32 = 28

used :: proc(value: int) -> int { return value + 1 }
unused :: proc() { fmt.println("unused") }

@(export)
kvist_repl_run :: proc "c" () {
    context = runtime.default_context()
    _ = used(41)
}
`
    source_map: [dynamic]kvist.Source_Map_Entry
    thin := repl_thin_generation_source(source, &source_map)
    defer delete(thin)
    defer kvist.source_map_slice_delete(source_map)

    testing.expect_value(t, strings.contains(thin, "kvist_repl_api_version"), true)
    testing.expect_value(t, strings.contains(thin, "kvist_repl_run"), true)
    testing.expect_value(t, strings.contains(thin, "used :: proc"), true)
    testing.expect_value(t, strings.contains(thin, "unused :: proc"), false)
    testing.expect_value(t, strings.contains(thin, `import fmt "core:fmt"`), false)
    testing.expect_value(t, strings.contains(thin, `import runtime "base:runtime"`), true)
}

@(test)
repl_direct_int_invocation_requires_typed_literal_call :: proc(t: ^testing.T) {
    emitted := `host.register_proc(host.ctx, "square", "proc(int:borrowed)->int", transmute(rawptr)square)
kvist_repl_result_value := square(11)
`
    command, ok := repl_direct_int_invocation("(square 11)", emitted)
    defer delete(command)
    testing.expect_value(t, ok, true)
    testing.expect_value(
        t,
        strings.has_prefix(command, REPL_WORKER_DIRECT_INT_PREFIX),
        true,
    )

    nested, nested_ok := repl_direct_int_invocation("(square (+ 10 1))", emitted)
    defer delete(nested)
    testing.expect_value(t, nested_ok, false)
}

@(test)
repl_direct_scalar_invocation_accepts_mixed_literals_and_data_history :: proc(
    t: ^testing.T,
) {
    emitted := `host.register_scalar_invoke(host.ctx, "mix", "proc(string:borrowed,int:borrowed,f64:borrowed,bool:borrowed)->string:owned", "value:string", mix__kvist_repl_scalar_invoke)
host.register_scalar_invoke(host.ctx, "read_record", "proc(Data:borrowed)->int", "value:int", read_record__kvist_repl_scalar_invoke)
kvist_repl_result_value := mix("x", 3, 1.5, true)
`
    mixed, mixed_ok := repl_direct_scalar_invocation(
        `(mix "x" 3 1.5 true)`,
        emitted,
    )
    defer delete(mixed)
    testing.expect_value(t, mixed_ok, true)
    testing.expect_value(
        t,
        strings.has_prefix(mixed, REPL_WORKER_DIRECT_SCALAR_PREFIX),
        true,
    )

    data_emitted := `host.register_scalar_invoke(host.ctx, "read_record", "proc(Data:borrowed)->int", "value:int", read_record__kvist_repl_scalar_invoke)
kvist_repl_result_value := read_record(kvist_repl_star_1)
`
    data, data_ok := repl_direct_scalar_invocation(
        `(read-record *1)`,
        data_emitted,
    )
    defer delete(data)
    testing.expect_value(t, data_ok, true)
    testing.expect_value(t, strings.contains(data, "\tr:"), true)

    nested, nested_ok := repl_direct_scalar_invocation(
        `(mix "x" (+ 1 2) 1.5 true)`,
        emitted,
    )
    defer delete(nested)
    testing.expect_value(t, nested_ok, false)
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
