// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist_hot_demo_support

import "core:dynlib"
import "core:fmt"
import kvist_hot "../kvist_hot"

Hot_Demo_Symbols :: struct {
    api_version: ^u32 `dynlib:"kvist_hot_api_version"`,
    state_size:  proc "c" () -> int `dynlib:"kvist_hot_state_size"`,
    state_align: proc "c" () -> int `dynlib:"kvist_hot_state_align"`,
    on_load:     proc "c" (state: rawptr, is_reload: bool) `dynlib:"kvist_hot_on_load"`,
    on_unload:   proc "c" (state: rawptr) `dynlib:"kvist_hot_on_unload"`,
    message:     proc "c" () -> cstring `dynlib:"hot_demo_message"`,
    tick:        proc "c" (state: rawptr) `dynlib:"hot_demo_tick"`,
    __handle:    dynlib.Library,
}

Hybrid_Demo_Symbols :: struct {
    api_version: ^u32 `dynlib:"kvist_hot_api_version"`,
    state_size:  proc "c" () -> int `dynlib:"kvist_hot_state_size"`,
    state_align: proc "c" () -> int `dynlib:"kvist_hot_state_align"`,
    on_load:     proc "c" (state: rawptr, is_reload: bool) `dynlib:"kvist_hot_on_load"`,
    on_unload:   proc "c" (state: rawptr) `dynlib:"kvist_hot_on_unload"`,
    message:     proc "c" () -> cstring `dynlib:"hybrid_demo_message"`,
    tick:        proc "c" (state: rawptr) `dynlib:"hybrid_demo_tick"`,
    __handle:    dynlib.Library,
}

Manifest_From_Symbols :: proc(symbols: $T) -> kvist_hot.Manifest {
    return kvist_hot.Manifest{
        api_version = symbols.api_version,
        state_size  = symbols.state_size,
        state_align = symbols.state_align,
        on_load     = symbols.on_load,
        on_unload   = symbols.on_unload,
    }
}

Call_Manifest_On_Load :: proc(manifest: kvist_hot.Manifest, state: ^$T, is_reload: bool) {
    manifest.on_load(rawptr(state), is_reload)
}

Call_Symbol_On_Unload :: proc(symbols: ^$T, state: ^$U) {
    symbols.on_unload(rawptr(state))
}

Call_Symbol_Tick :: proc(symbols: ^$T, state: ^$U) {
    symbols.tick(rawptr(state))
}

Call_Symbol_Message :: proc(symbols: ^$T) -> string {
    return string(symbols.message())
}

Finish_Reload :: proc(
    symbols: ^$TSymbols,
    state: ^$TState,
    expected_state_size, expected_state_align: int,
    result: kvist_hot.Reload_Result,
    generation: int,
    is_reload: bool,
) -> bool {
    manifest := Manifest_From_Symbols(symbols^)
    validation_err, valid := kvist_hot.validate_manifest(manifest, expected_state_size, expected_state_align)
    if !valid {
        fmt.println("[host] manifest validation failed:", validation_err)
        delete(validation_err)
        dynlib.unload_library(symbols.__handle)
        kvist_hot.cleanup_shadow_copy(result.shadow_path)
        delete(result.shadow_path)
        return false
    }

    Call_Manifest_On_Load(manifest, state, is_reload)
    fmt.printf("[host] loaded generation %d from %s (%d symbols)\n", generation, result.shadow_path, result.symbol_count)
    kvist_hot.cleanup_shadow_copy(result.shadow_path)
    delete(result.shadow_path)
    return true
}
