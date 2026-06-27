// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import mem "core:mem"
import time "core:time"

REPS :: 200
MAP_N :: 50_000
KEY_MOD :: 1024

report :: proc(name: string, elapsed: time.Duration, checksum: int, track: ^mem.Tracking_Allocator) {
    fmt.printfln(
        "%-16s %9.3f ms allocs=%8v total=%10v peak=%9v live=%v checksum=%v",
        name,
        time.duration_milliseconds(elapsed),
        track.total_allocation_count,
        track.total_memory_allocated,
        track.peak_memory_allocated,
        track.current_memory_allocated,
        checksum,
    )
}

run_one :: proc(name: string, checksum: int, start: time.Tick, track: ^mem.Tracking_Allocator) {
    report(name, time.tick_since(start), checksum, track)
}

bench_map_update_bang :: proc(reps, n: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        counts := make(map[int]int)
        for j := 0; j < n; j += 1 {
            counts[j % KEY_MOD] += 1
        }
        checksum += counts[17]
        checksum += counts[511]
        delete(counts)
    }
    return checksum
}

main :: proc() {
    fmt.printfln("REPS=%v MAP_N=%v KEY_MOD=%v", REPS, MAP_N, KEY_MOD)
    old_allocator := context.allocator
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, old_allocator, old_allocator)
    defer mem.tracking_allocator_destroy(&track)
    context.allocator = mem.tracking_allocator(&track)
    defer context.allocator = old_allocator

    mem.tracking_allocator_reset(&track)
    start := time.tick_now()
    run_one("map-update!", bench_map_update_bang(REPS, MAP_N), start, &track)
}
