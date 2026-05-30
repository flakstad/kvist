package kvist_hot

import "core:dynlib"
import "core:time"

MANIFEST_API_VERSION :: u32(1)

Manifest :: struct {
    api_version: ^u32 `dynlib:"kvist_hot_api_version"`,
    state_size:  proc "c" () -> int `dynlib:"kvist_hot_state_size"`,
    state_align: proc "c" () -> int `dynlib:"kvist_hot_state_align"`,
    on_load:     proc "c" (state: rawptr, is_reload: bool) `dynlib:"kvist_hot_on_load"`,
    on_unload:   proc "c" (state: rawptr) `dynlib:"kvist_hot_on_unload"`,
}

Reload_Result :: struct {
    shadow_path:  string,
    symbol_count: int,
}

Reloader :: struct {
    source_path:       string,
    symbol_prefix:     string,
    handle_field_name: string,
    generation:        int,
    last_mtime:        time.Time,
    has_loaded:        bool,
}
