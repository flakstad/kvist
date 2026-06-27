// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import mem "core:mem"
import time "core:time"

STRUCT_REPS :: 40
STRUCT_N :: 2_000
REPS :: 80
ARRAY_N :: 8_000
MAP_N :: 8_000

Score :: struct {
    value: int,
    bonus: int,
}

report :: proc(name: string, elapsed: time.Duration, checksum: int, track: ^mem.Tracking_Allocator) {
    fmt.printfln(
        "%-19s %9.3f ms allocs=%8v total=%10v peak=%9v live=%v checksum=%v",
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

bump_score :: proc(score: Score) -> Score {
    updated := score
    updated.value = updated.value + 3
    updated.bonus = updated.bonus + 1
    return updated
}

bump_score_bang :: proc(score: ^Score) {
    score.value = score.value + 3
    score.bonus = score.bonus + 1
}

bench_struct_update :: proc(reps, n: int) -> int {
    base := make([dynamic]Score, 0, n)
    for j := 0; j < n; j += 1 {
        append(&base, Score{value = j + 1, bonus = j % 7})
    }
    defer delete(base)

    checksum := 0
    for i := 0; i < reps; i += 1 {
        scores := make([dynamic]Score, 0, len(base))
        append(&scores, ..base[:])
        for j := 0; j < n; j += 1 {
            scores[j] = bump_score(scores[j])
        }
        checksum += scores[n-1].value
        checksum += scores[n-1].bonus
        delete(scores)
    }
    return checksum
}

bench_pointer_update :: proc(reps, n: int) -> int {
    base := make([dynamic]Score, 0, n)
    for j := 0; j < n; j += 1 {
        append(&base, Score{value = j + 1, bonus = j % 7})
    }
    defer delete(base)

    checksum := 0
    for i := 0; i < reps; i += 1 {
        scores := make([dynamic]Score, 0, len(base))
        append(&scores, ..base[:])
        for j := 0; j < n; j += 1 {
            bump_score_bang(&scores[j])
        }
        checksum += scores[n-1].value
        checksum += scores[n-1].bonus
        delete(scores)
    }
    return checksum
}

bench_array_update_bang :: proc(reps, n: int) -> int {
    base := make([dynamic]int, 0, n)
    for j := 0; j < n; j += 1 {
        append(&base, j)
    }
    defer delete(base)

    checksum := 0
    for i := 0; i < reps; i += 1 {
        xs := make([dynamic]int, 0, len(base))
        append(&xs, ..base[:])
        for j := 0; j < n; j += 1 {
            xs[j] = xs[j] + 1
        }
        checksum += xs[n-1]
        delete(xs)
    }
    return checksum
}

bench_map_update_bang :: proc(reps, n: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        counts := make(map[int]int)
        for j := 0; j < n; j += 1 {
            counts[j % 1024] += 1
        }
        checksum += counts[17]
        delete(counts)
    }
    return checksum
}

main :: proc() {
    fmt.printfln(
        "STRUCT_REPS=%v STRUCT_N=%v REPS=%v ARRAY_N=%v MAP_N=%v",
        STRUCT_REPS,
        STRUCT_N,
        REPS,
        ARRAY_N,
        MAP_N,
    )
    old_allocator := context.allocator
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, old_allocator, old_allocator)
    defer mem.tracking_allocator_destroy(&track)
    context.allocator = mem.tracking_allocator(&track)
    defer context.allocator = old_allocator

    mem.tracking_allocator_reset(&track)
    start := time.tick_now()
    run_one("struct-update", bench_struct_update(STRUCT_REPS, STRUCT_N), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("pointer-update", bench_pointer_update(STRUCT_REPS, STRUCT_N), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("array-update!", bench_array_update_bang(REPS, ARRAY_N), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("map-update!", bench_map_update_bang(REPS, MAP_N), start, &track)
}
