package hot_reload_demo_host

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"
import kvist_hot "../../../src/kvist_hot"
import shared "../shared"

Demo_Symbols :: struct {
    api_version: ^u32 `dynlib:"kvist_hot_api_version"`,
    state_size:  proc "c" () -> int `dynlib:"kvist_hot_state_size"`,
    state_align: proc "c" () -> int `dynlib:"kvist_hot_state_align"`,
    on_load:     proc "c" (state: rawptr, is_reload: bool) `dynlib:"kvist_hot_on_load"`,
    on_unload:   proc "c" (state: rawptr) `dynlib:"kvist_hot_on_unload"`,
    message:     proc "c" () -> cstring `dynlib:"hot_demo_message"`,
    tick:        proc "c" (state: rawptr) `dynlib:"hot_demo_tick"`,
    __handle:    dynlib.Library,
}

manifest_from_symbols :: proc(symbols: Demo_Symbols) -> kvist_hot.Manifest {
    return kvist_hot.Manifest{
        api_version = symbols.api_version,
        state_size = symbols.state_size,
        state_align = symbols.state_align,
        on_load = symbols.on_load,
        on_unload = symbols.on_unload,
    }
}

library_path :: proc() -> string {
    return kvist_hot.library_filename("build/hot_reload_demo/hot_demo")
}

finish_reload :: proc(symbols: ^Demo_Symbols, state: ^shared.State, result: kvist_hot.Reload_Result, generation: int, is_reload: bool) -> bool {
    manifest := manifest_from_symbols(symbols^)
    validation_err, valid := kvist_hot.validate_manifest(manifest, size_of(shared.State), align_of(shared.State))
    if !valid {
        fmt.println("[host] manifest validation failed:", validation_err)
        delete(validation_err)
        dynlib.unload_library(symbols.__handle)
        kvist_hot.cleanup_shadow_copy(result.shadow_path)
        delete(result.shadow_path)
        return false
    }

    if is_reload {
        manifest.on_load(state, true)
    } else {
        manifest.on_load(state, false)
    }

    fmt.printf("[host] loaded generation %d from %s (%d symbols)\n", generation, result.shadow_path, result.symbol_count)
    kvist_hot.cleanup_shadow_copy(result.shadow_path)
    delete(result.shadow_path)
    return true
}

main :: proc() {
    path := library_path()
    defer delete(path)

    state := shared.State{}
    symbols := Demo_Symbols{}
    reloader, reloader_err, reloader_ok := kvist_hot.new_reloader(path)
    if !reloader_ok {
        fmt.println(reloader_err)
        delete(reloader_err)
        fmt.println("build it first with:")
        fmt.printf("  odin build examples/hot_reload_demo/module -build-mode:dll -out:%s\n", path)
        return
    }

    initial_result, initial_err, initial_ok := kvist_hot.load_initial(&reloader, &symbols)
    if !initial_ok {
        fmt.println("[host] initial load failed:", initial_err)
        delete(initial_err)
        return
    }
    if !finish_reload(&symbols, &state, initial_result, reloader.generation, false) {
        return
    }

    fmt.println("[host] running. rebuild the module shared library to reload in place.")
    fmt.println("[host] state lives in the host and survives reload.")

    for {
        symbols.tick(rawptr(&state))
        fmt.printf("[tick] module=%s tick=%d reloads=%d unloads=%d message=%s\n",
            string(symbols.message()),
            state.tick_count,
            state.reload_count,
            state.unload_count,
            state.last_message,
        )

        time.sleep(1 * time.Second)

        changed, reload_result, reload_err, reload_ok := kvist_hot.reload_if_source_changed(&reloader, &symbols)
        if !reload_ok {
            fmt.println("[host] reload failed:", reload_err)
            delete(reload_err)
            continue
        }
        if changed {
            symbols.on_unload(rawptr(&state))
            if finish_reload(&symbols, &state, reload_result, reloader.generation, true) {
                fmt.printf("[host] after reload: ticks=%d reloads=%d unloads=%d message=%s\n",
                    state.tick_count,
                    state.reload_count,
                    state.unload_count,
                    state.last_message,
                )
            }
        }
    }
}
