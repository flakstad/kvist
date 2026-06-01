package main

import "core:fmt"
import "core:strings"
import mem "core:mem"
import time "core:time"

COUNT :: 512
REPS :: 250
STRING_REPS :: 1_200

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

build_map_overrides :: proc() -> map[int]int {
    out := make(map[int]int, 3)
    out[2] = 20
    out[4] = 40
    out[6] = 60
    return out
}

build_map_mutable :: proc() -> map[int]int {
    out := make(map[int]int, 6)
    out[0] = 1
    out[1] = 2
    out[2] = 3
    out[3] = 4
    return out
}

build_set_rhs :: proc() -> map[int]bool {
    out := make(map[int]bool, 5)
    out[4] = true
    out[5] = true
    out[6] = true
    out[7] = true
    out[8] = true
    return out
}

build_set_mutable :: proc() -> map[int]bool {
    out := make(map[int]bool, 6)
    out[1] = true
    out[2] = true
    out[3] = true
    out[4] = true
    out[5] = true
    out[6] = true
    return out
}

build_even_set :: proc() -> map[int]bool {
    out := make(map[int]bool, 5)
    out[2] = true
    out[4] = true
    out[6] = true
    out[8] = true
    out[10] = true
    return out
}

bench_str_direct :: proc(reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        source := "  Kvist,odin,core,odin  "
        trimmed := strings.trim_space(source)
        parts := strings.split(trimmed, ",")
        joined, _ := strings.join(parts[:], "-")
        replaced := kvist_str_replace(joined, "odin", "ODIN", 1)
        lowered := strings.to_lower(replaced)
        uppered := strings.to_upper(lowered)

        checksum += len(trimmed)
        checksum += len(parts)
        checksum += strings.index(joined, "-")
        checksum += strings.last_index(joined, "-")
        checksum += len(uppered[6:])
        if strings.has_prefix(trimmed, "Kvist") {
            checksum += 1
        }
        if strings.has_suffix(trimmed, "odin") {
            checksum += 1
        }
        if strings.contains(replaced, "ODIN") {
            checksum += 1
        }

        delete(uppered)
        delete(lowered)
        delete(replaced)
        delete(joined)
        delete(parts)
    }
    return checksum
}

bench_map_direct :: proc(reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        overrides := build_map_overrides()
        mutable := build_map_mutable()
        mutable[1] = 2
        delete_key(&mutable, 0)
        for key, value in overrides {
            mutable[key] = value
        }
        mutable[COUNT] = 99

        checksum += mutable[1]
        checksum += mutable[2]
        checksum += mutable[COUNT]
        checksum += 6
        if mutable[4] != 0 {
            checksum += 1
        }

        delete(mutable)
        delete(overrides)
    }
    return checksum
}

bench_set_direct :: proc(reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        rhs := build_set_rhs()
        mutable := build_set_mutable()
        evens := build_even_set()
        removed := make(map[int]bool, 1)
        removed[2] = true

        mutable[COUNT+1] = true
        delete_key(&mutable, 0)
        for value in rhs {
            mutable[value] = true
        }
        for value in mutable {
            if !evens[value] {
                delete_key(&mutable, value)
            }
        }
        for value in removed {
            delete_key(&mutable, value)
        }

        checksum += 3
        if mutable[4] {
            checksum += 1
        }
        if mutable[6] {
            checksum += 1
        }
        if mutable[8] {
            checksum += 1
        }

        delete(removed)
        delete(evens)
        delete(mutable)
        delete(rhs)
    }
    return checksum
}

kvist_str_replace :: proc(s, old, new: string, n: int) -> string {
    replaced, _ := strings.replace(s, old, new, n, context.allocator)
    return replaced
}

main :: proc() {
    old_allocator := context.allocator

    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, old_allocator, old_allocator)
    defer mem.tracking_allocator_destroy(&track)
    context.allocator = mem.tracking_allocator(&track)
    defer context.allocator = old_allocator

    mem.tracking_allocator_reset(&track)
    start := time.tick_now()
    run_one("str-direct", bench_str_direct(STRING_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("map-direct", bench_map_direct(REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("set-direct", bench_set_direct(REPS), start, &track)
}
