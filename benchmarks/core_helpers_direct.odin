package main

import "core:fmt"
import mem "core:mem"
import time "core:time"

N :: 50_000
REPS :: 400
KEY_COUNT :: 20_000
STRIDE :: 7

report :: proc(name: string, elapsed: time.Duration, checksum: int, track: ^mem.Tracking_Allocator) {
    fmt.printfln(
        "%-17s %9.3f ms allocs=%8v total=%10v peak=%9v live=%v checksum=%v",
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

build_ints :: proc(n: int) -> [dynamic]int {
    xs := make([dynamic]int, 0, n)
    for i := 0; i < n; i += 1 {
        append(&xs, i)
    }
    return xs
}

build_keys :: proc(n: int) -> [dynamic]int {
    keys := make([dynamic]int, 0, n)
    for i := 0; i < n; i += 1 {
        append(&keys, (i * 13) % N)
    }
    return keys
}

build_lookup :: proc(n: int) -> map[int]int {
    lookup := make(map[int]int, n)
    for i := 0; i < n; i += 1 {
        lookup[i] = i * 3
    }
    return lookup
}

bench_index_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        total := 0
        n := len(xs)
        for j := 0; j < n; j += STRIDE {
            total += xs[j]
        }
        checksum += total
    }
    return checksum
}

bench_slice_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        prefix := xs[128:8192]
        suffix := xs[8192:]
        total := len(prefix) + len(suffix) + prefix[0] + suffix[0]
        checksum += total
    }
    return checksum
}

get_or_default :: proc(m: map[int]int, key, default: int) -> int {
    value, ok := m[key]
    if ok {
        return value
    }
    return default
}

bench_map_direct :: proc(lookup: map[int]int, keys: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        total := 0
        n := len(keys)
        for j := 0; j < n; j += 1 {
            key := keys[j]
            if key in lookup {
                total += get_or_default(lookup, key, 0)
            }
            total += get_or_default(lookup, key+N, -1)
        }
        checksum += total
    }
    return checksum
}

main :: proc() {
    xs := build_ints(N)
    keys := build_keys(KEY_COUNT)
    lookup := build_lookup(N)
    defer delete(xs)
    defer delete(keys)
    defer delete(lookup)

    old_allocator := context.allocator
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, old_allocator, old_allocator)
    defer mem.tracking_allocator_destroy(&track)
    context.allocator = mem.tracking_allocator(&track)
    defer context.allocator = old_allocator

    mem.tracking_allocator_reset(&track)
    start := time.tick_now()
    run_one("index-direct", bench_index_direct(xs[:], REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("slice-direct", bench_slice_direct(xs[:], REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("map-direct", bench_map_direct(lookup, keys[:], REPS), start, &track)
}
