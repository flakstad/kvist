package kvist_hot

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

library_filename :: proc(base_name: string) -> string {
    return strings.clone(fmt.tprintf("%s.%s", base_name, dynlib.LIBRARY_FILE_EXTENSION))
}

shadow_library_path :: proc(source_path: string, generation: int) -> (string, string, bool) {
    dir, _ := os.split_path(source_path)
    stem := os.stem(source_path)
    ext := os.ext(source_path)

    shadow_name := fmt.tprintf("%s.hot.%d%s", stem, generation, ext)
    if dir == "" {
        return strings.clone(shadow_name), "", true
    }
    shadow_path, join_err := os.join_path({dir, shadow_name}, context.allocator)
    if join_err != nil {
        return "", strings.clone(fmt.tprintf("could not join shadow library path: %v", join_err)), false
    }
    return shadow_path, "", true
}

stage_shadow_copy :: proc(source_path: string, generation: int) -> (string, os.Error, bool) {
    shadow_path, _, path_ok := shadow_library_path(source_path, generation)
    if !path_ok {
        return "", os.Error{}, false
    }

    if os.exists(shadow_path) {
        _ = os.remove(shadow_path)
    }

    copy_err := os.copy_file(shadow_path, source_path)
    if copy_err != nil {
        delete(shadow_path)
        return "", copy_err, false
    }
    return shadow_path, nil, true
}

cleanup_shadow_copy :: proc(shadow_path: string) {
    if shadow_path == "" {
        return
    }
    if os.exists(shadow_path) {
        _ = os.remove(shadow_path)
    }
}

validate_manifest :: proc(manifest: Manifest, expected_state_size, expected_state_align: int) -> (string, bool) {
    if manifest.api_version == nil {
        return strings.clone("missing kvist_hot_api_version export"), false
    }
    if manifest.api_version^ != MANIFEST_API_VERSION {
        return strings.clone(fmt.tprintf("kvist_hot API version mismatch: expected %d got %d", MANIFEST_API_VERSION, manifest.api_version^)), false
    }
    if manifest.state_size == nil {
        return strings.clone("missing kvist_hot_state_size export"), false
    }
    if manifest.state_align == nil {
        return strings.clone("missing kvist_hot_state_align export"), false
    }
    if manifest.on_load == nil {
        return strings.clone("missing kvist_hot_on_load export"), false
    }
    if manifest.on_unload == nil {
        return strings.clone("missing kvist_hot_on_unload export"), false
    }
    if manifest.state_size() != expected_state_size {
        return strings.clone(fmt.tprintf("state size mismatch: expected %d got %d", expected_state_size, manifest.state_size())), false
    }
    if manifest.state_align() != expected_state_align {
        return strings.clone(fmt.tprintf("state align mismatch: expected %d got %d", expected_state_align, manifest.state_align())), false
    }
    return "", true
}

reload_symbols :: proc(
    symbol_table: ^$T,
    source_path: string,
    generation: int,
    symbol_prefix := "",
    handle_field_name := "__handle",
) -> (Reload_Result, string, bool) {
    shadow_path, copy_err, copy_ok := stage_shadow_copy(source_path, generation)
    if !copy_ok {
        return Reload_Result{}, strings.clone(fmt.tprintf("could not stage shadow copy: %v", copy_err)), false
    }

    count, ok := dynlib.initialize_symbols(symbol_table, shadow_path, symbol_prefix, handle_field_name)
    if !ok {
        cleanup_shadow_copy(shadow_path)
        delete(shadow_path)
        return Reload_Result{}, strings.clone(dynlib.last_error()), false
    }

    return Reload_Result{
        shadow_path = shadow_path,
        symbol_count = count,
    }, "", true
}

new_reloader :: proc(source_path: string, symbol_prefix := "", handle_field_name := "__handle") -> (Reloader, string, bool) {
    mtime, mtime_err := os.modification_time_by_path(source_path)
    if mtime_err != nil {
        return Reloader{}, strings.clone(fmt.tprintf("could not stat reload source %q: %v", source_path, mtime_err)), false
    }

    return Reloader{
        source_path = source_path,
        symbol_prefix = symbol_prefix,
        handle_field_name = handle_field_name,
        generation = 1,
        last_mtime = mtime,
        has_loaded = false,
    }, "", true
}

load_initial :: proc(reloader: ^Reloader, symbol_table: ^$T) -> (Reload_Result, string, bool) {
    result, reload_err, reload_ok := reload_symbols(
        symbol_table,
        reloader.source_path,
        reloader.generation,
        reloader.symbol_prefix,
        reloader.handle_field_name,
    )
    if !reload_ok {
        return Reload_Result{}, reload_err, false
    }

    reloader.has_loaded = true
    return result, "", true
}

reload_if_source_changed :: proc(reloader: ^Reloader, symbol_table: ^$T) -> (bool, Reload_Result, string, bool) {
    current_mtime, current_err := os.modification_time_by_path(reloader.source_path)
    if current_err != nil {
        return false, Reload_Result{}, strings.clone(fmt.tprintf("could not stat reload source %q: %v", reloader.source_path, current_err)), false
    }

    if !reloader.has_loaded {
        result, reload_err, reload_ok := load_initial(reloader, symbol_table)
        return true, result, reload_err, reload_ok
    }

    if time.time_to_unix_nano(current_mtime) == time.time_to_unix_nano(reloader.last_mtime) {
        return false, Reload_Result{}, "", true
    }

    previous_generation := reloader.generation
    previous_mtime := reloader.last_mtime

    reloader.generation += 1
    result, reload_err, reload_ok := reload_symbols(
        symbol_table,
        reloader.source_path,
        reloader.generation,
        reloader.symbol_prefix,
        reloader.handle_field_name,
    )
    if !reload_ok {
        reloader.generation = previous_generation
        reloader.last_mtime = previous_mtime
        return true, Reload_Result{}, reload_err, false
    }

    reloader.last_mtime = current_mtime
    return true, result, "", true
}
