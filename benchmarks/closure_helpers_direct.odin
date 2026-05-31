package main

import "core:fmt"
import mem "core:mem"
import time "core:time"

MAP_N :: 120_000
MAP_REPS :: 120
MAP_BANG_N :: 80_000
MAP_BANG_REPS :: 80

report :: proc(name: string, elapsed: time.Duration, checksum: int, track: ^mem.Tracking_Allocator) {
    fmt.printfln(
        "%-22s %9.3f ms allocs=%8v total=%10v peak=%9v live=%v checksum=%v",
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

make_base :: proc(n: int) -> [dynamic]int {
    xs := make([dynamic]int, 0, n)
    for i := 0; i < n; i += 1 {
        append(&xs, i)
    }
    return xs
}

map_with_context_1 :: proc(f: proc(c1: int, x: int) -> int, c1: int, xs: []int) -> [dynamic]int {
    out := make([dynamic]int, 0, len(xs))
    for x in xs {
        append(&out, f(c1, x))
    }
    return out
}

filter_with_context_1 :: proc(pred: proc(c1: int, x: int) -> bool, c1: int, xs: []int) -> [dynamic]int {
    out := make([dynamic]int, 0, len(xs))
    for x in xs {
        if pred(c1, x) {
            append(&out, x)
        }
    }
    return out
}

map_in_place_with_context_1 :: proc(f: proc(c1: int, x: int) -> int, c1: int, xs: []int) {
    for i := 0; i < len(xs); i += 1 {
        xs[i] = f(c1, xs[i])
    }
}

add_offset :: proc(offset, x: int) -> int {
    return x + offset
}

greater_than_limit :: proc(limit, x: int) -> bool {
    return x > limit
}

bench_map_context_helper :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    offset := 7
    for i := 0; i < reps; i += 1 {
        mapped := map_with_context_1(add_offset, offset, xs)
        checksum += mapped[len(mapped)-1]
        delete(mapped)
    }
    return checksum
}

bench_map_loop :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    offset := 7
    for i := 0; i < reps; i += 1 {
        mapped := make([dynamic]int, 0, len(xs))
        for x in xs {
            append(&mapped, x + offset)
        }
        checksum += mapped[len(mapped)-1]
        delete(mapped)
    }
    return checksum
}

bench_filter_context_helper :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    limit := 60_000
    for i := 0; i < reps; i += 1 {
        filtered := filter_with_context_1(greater_than_limit, limit, xs)
        checksum += len(filtered)
        delete(filtered)
    }
    return checksum
}

bench_filter_loop :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    limit := 60_000
    for i := 0; i < reps; i += 1 {
        filtered := make([dynamic]int, 0, len(xs))
        for x in xs {
            if x > limit {
                append(&filtered, x)
            }
        }
        checksum += len(filtered)
        delete(filtered)
    }
    return checksum
}

bench_map_bang_context_helper :: proc(base: []int, reps: int) -> int {
    checksum := 0
    offset := 7
    for i := 0; i < reps; i += 1 {
        xs := make([dynamic]int, 0, len(base))
        append(&xs, ..base)
        map_in_place_with_context_1(add_offset, offset, xs[:])
        checksum += xs[len(xs)-1]
        delete(xs)
    }
    return checksum
}

bench_map_bang_loop :: proc(base: []int, reps: int) -> int {
    checksum := 0
    offset := 7
    for i := 0; i < reps; i += 1 {
        xs := make([dynamic]int, 0, len(base))
        append(&xs, ..base)
        for j := 0; j < len(xs); j += 1 {
            xs[j] += offset
        }
        checksum += xs[len(xs)-1]
        delete(xs)
    }
    return checksum
}

main :: proc() {
    fmt.printfln(
        "MAP_N=%v MAP_REPS=%v MAP_BANG_N=%v MAP_BANG_REPS=%v",
        MAP_N,
        MAP_REPS,
        MAP_BANG_N,
        MAP_BANG_REPS,
    )
    old_allocator := context.allocator
    map_base := make_base(MAP_N)
    bang_base := make_base(MAP_BANG_N)
    defer delete(map_base)
    defer delete(bang_base)

    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, old_allocator, old_allocator)
    defer mem.tracking_allocator_destroy(&track)
    context.allocator = mem.tracking_allocator(&track)
    defer context.allocator = old_allocator

    mem.tracking_allocator_reset(&track)
    start := time.tick_now()
    run_one("map-helper-ctx", bench_map_context_helper(map_base[:], MAP_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("map-loop", bench_map_loop(map_base[:], MAP_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("filter-helper-ctx", bench_filter_context_helper(map_base[:], MAP_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("filter-loop", bench_filter_loop(map_base[:], MAP_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("map!-helper-ctx", bench_map_bang_context_helper(bang_base[:], MAP_BANG_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("map!-loop", bench_map_bang_loop(bang_base[:], MAP_BANG_REPS), start, &track)
}
