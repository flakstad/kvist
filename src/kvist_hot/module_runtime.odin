package kvist_hot

State_Size :: proc "contextless"($T: typeid) -> int {
    return size_of(T)
}

State_Align :: proc "contextless"($T: typeid) -> int {
    return align_of(T)
}

On_Load :: proc "contextless"($T: typeid, state: rawptr, is_reload: bool, initial_message: string) {
    app_state := (^T)(state)
    if is_reload {
        app_state.reload_count += 1
    } else {
        app_state.last_message = initial_message
    }
}

On_Unload :: proc "contextless"($T: typeid, state: rawptr) {
    app_state := (^T)(state)
    app_state.unload_count += 1
}

Tick :: proc "contextless"($T: typeid, state: rawptr, message: string) {
    app_state := (^T)(state)
    app_state.tick_count += 1
    app_state.last_message = message
}
