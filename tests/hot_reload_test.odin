package tests

import "core:os"
import "core:testing"
import kvist_hot "../src/kvist_hot"

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
