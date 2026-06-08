package tests

import "core:dynlib"
import "core:os"
import "core:testing"
import kvist_hot "../src/kvist_hot"
import olive_reload "../src/olive_reload"

hot_test_on_load_calls: int
hot_test_on_unload_calls: int
hot_test_last_is_reload: bool

Hot_Test_State :: struct {
    load_count:   int,
    unload_count: int,
}

Hot_Test_Symbols :: struct {
    api_version: ^u32,
    state_size:  proc "c" () -> int,
    state_align: proc "c" () -> int,
    on_load:     proc "c" (state: rawptr, is_reload: bool),
    on_unload:   proc "c" (state: rawptr),
    __handle:    dynlib.Library,
}

hot_test_state_size :: proc "c" () -> int {
    return size_of(Hot_Test_State)
}

hot_test_state_align :: proc "c" () -> int {
    return align_of(Hot_Test_State)
}

hot_test_on_load :: proc "c" (state: rawptr, is_reload: bool) {
    hot_test_on_load_calls += 1
    hot_test_last_is_reload = is_reload
    typed_state := (^Hot_Test_State)(state)
    typed_state.load_count += 1
}

hot_test_on_unload :: proc "c" (state: rawptr) {
    hot_test_on_unload_calls += 1
    typed_state := (^Hot_Test_State)(state)
    typed_state.unload_count += 1
}

@(test)
hot_reload_shadow_library_path_includes_generation :: proc(t: ^testing.T) {
    path, err, ok := kvist_hot.shadow_library_path("build/hot_demo.dylib", 7)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, err, "")
    if !ok {
        return
    }
    defer delete(path)

    testing.expect_value(t, path, "build/hot_demo.hot.7.dylib")
}

@(test)
hot_reload_validates_manifest_contract :: proc(t: ^testing.T) {
    version := kvist_hot.MANIFEST_API_VERSION

    state_size :: proc "c" () -> int { return 24 }
    state_align :: proc "c" () -> int { return 8 }
    on_load :: proc "c" (state: rawptr, is_reload: bool) {}
    on_unload :: proc "c" (state: rawptr) {}

    manifest := kvist_hot.Manifest{
        api_version = &version,
        state_size = state_size,
        state_align = state_align,
        on_load = on_load,
        on_unload = on_unload,
    }

    err, ok := kvist_hot.validate_manifest(manifest, 24, 8)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, err, "")

    bad_err, bad_ok := kvist_hot.validate_manifest(manifest, 16, 8)
    testing.expect_value(t, bad_ok, false)
    testing.expect_value(t, bad_err, "state size mismatch: expected 16 got 24")
    delete(bad_err)
}

@(test)
hot_reload_reloader_tracks_path_and_generation :: proc(t: ^testing.T) {
    temp_dir, temp_dir_err := os.temp_directory(context.allocator)
    testing.expect_value(t, temp_dir_err == nil, true)
    if temp_dir_err != nil {
        return
    }
    defer delete(temp_dir)

    temp_path, join_err := os.join_path({temp_dir, "kvist_hot_reloader_test.txt"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(temp_path)
    defer _ = os.remove(temp_path)

    write_err := os.write_entire_file(temp_path, "v1")
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    reloader, err, ok := kvist_hot.new_reloader(temp_path)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, err, "")
    testing.expect_value(t, reloader.source_path, temp_path)
    testing.expect_value(t, reloader.generation, 1)
    testing.expect_value(t, reloader.has_loaded, false)
}

@(test)
hot_reload_apply_reload_result_runs_on_load_and_cleans_shadow_copy :: proc(t: ^testing.T) {
    hot_test_on_load_calls = 0
    hot_test_last_is_reload = false

    temp_dir, temp_dir_err := os.temp_directory(context.allocator)
    testing.expect_value(t, temp_dir_err == nil, true)
    if temp_dir_err != nil {
        return
    }
    defer delete(temp_dir)

    shadow_path, join_err := os.join_path({temp_dir, "kvist_hot_apply_test.dylib"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }

    write_err := os.write_entire_file(shadow_path, "shadow")
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    version := kvist_hot.MANIFEST_API_VERSION
    symbols := Hot_Test_Symbols{
        api_version = &version,
        state_size = hot_test_state_size,
        state_align = hot_test_state_align,
        on_load = hot_test_on_load,
        on_unload = hot_test_on_unload,
    }
    reloader := kvist_hot.Reloader{handle_field_name = "__handle"}
    state := Hot_Test_State{}

    err, ok := kvist_hot.apply_reload_result(&reloader, &symbols, &state, kvist_hot.Reload_Result{
        shadow_path = shadow_path,
        symbol_count = 7,
    }, true)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, err, "")
    testing.expect_value(t, hot_test_on_load_calls, 1)
    testing.expect_value(t, hot_test_last_is_reload, true)
    testing.expect_value(t, state.load_count, 1)
    testing.expect_value(t, os.exists(shadow_path), false)
}

@(test)
hot_reload_unload_current_module_runs_on_unload :: proc(t: ^testing.T) {
    hot_test_on_unload_calls = 0

    version := kvist_hot.MANIFEST_API_VERSION
    symbols := Hot_Test_Symbols{
        api_version = &version,
        state_size = hot_test_state_size,
        state_align = hot_test_state_align,
        on_load = hot_test_on_load,
        on_unload = hot_test_on_unload,
    }
    state := Hot_Test_State{}

    kvist_hot.unload_current_module(&symbols, &state)

    testing.expect_value(t, hot_test_on_unload_calls, 1)
    testing.expect_value(t, state.unload_count, 1)
}

@(test)
reload_run_host_checkpoint_without_reloader_returns_false :: proc(t: ^testing.T) {
    host := olive_reload.Run_Host{}

    should_stop := olive_reload.checkpoint(&host)

    testing.expect_value(t, should_stop, false)
    testing.expect_value(t, host.checkpoint_error, "")
}
