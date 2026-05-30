package hot_reload_demo_module

import shared "../shared"

@(export)
kvist_hot_api_version: u32 = 1

@(export)
kvist_hot_state_size :: proc "c" () -> int {
    return size_of(shared.State)
}

@(export)
kvist_hot_state_align :: proc "c" () -> int {
    return align_of(shared.State)
}

@(export)
kvist_hot_on_load :: proc "c" (state: rawptr, is_reload: bool) {
    app_state := (^shared.State)(state)
    if is_reload {
        app_state.reload_count += 1
    } else {
        app_state.last_message = "module v1 loaded"
    }
}

@(export)
kvist_hot_on_unload :: proc "c" (state: rawptr) {
    app_state := (^shared.State)(state)
    app_state.unload_count += 1
}

@(export)
hot_demo_message :: proc "c" () -> cstring {
    return "module v1"
}

@(export)
hot_demo_tick :: proc "c" (state: rawptr) {
    app_state := (^shared.State)(state)
    app_state.tick_count += 1
    app_state.last_message = string(hot_demo_message())
}
