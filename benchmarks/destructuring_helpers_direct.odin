package main

import "core:fmt"
import mem "core:mem"
import time "core:time"

POINT_N :: 32_768
REPS :: 400

Point :: struct {
    x: int,
    y: int,
    z: int,
    w: int,
}

report :: proc(name: string, elapsed: time.Duration, checksum: int, track: ^mem.Tracking_Allocator) {
    fmt.printfln("%-18s %9.3f ms allocs=%8v total=%10v peak=%9v live=%v checksum=%v",
        name,
        time.duration_milliseconds(elapsed),
        track.total_allocation_count,
        track.total_memory_allocated,
        track.peak_memory_allocated,
        track.current_memory_allocated,
        checksum)
}

run_one :: proc(name: string, checksum: int, start: time.Tick, track: ^mem.Tracking_Allocator) {
    report(name, time.tick_since(start), checksum, track)
}

build_points :: proc(n: int) -> [dynamic]Point {
    points := make([dynamic]Point, 0, n)
    for i in 0..<n {
        append(&points, Point{x = i, y = i + 1, z = i + 2, w = i + 3})
    }
    return points
}

bench_local_direct :: proc(points: []Point, reps: int) -> int {
    checksum := 0
    for _ in 0..<reps {
        for j in 0..<len(points) {
            point := points[j]
            checksum += point.x
            checksum += point.y
            checksum += point.z
            checksum += point.w
        }
    }
    return checksum
}

bench_local_bound :: proc(points: []Point, reps: int) -> int {
    checksum := 0
    for _ in 0..<reps {
        for j in 0..<len(points) {
            point := points[j]
            x := point.x
            y := point.y
            z := point.z
            w := point.w
            checksum += x
            checksum += y
            checksum += z
            checksum += w
        }
    }
    return checksum
}

bench_expr_direct :: proc(points: []Point, reps: int) -> int {
    checksum := 0
    n := len(points)
    for i in 0..<reps {
        for j in 0..<n {
            idx := (j*7 + i) % n
            point := points[idx]
            checksum += point.x
            checksum += point.y
            checksum += point.z
            checksum += point.w
        }
    }
    return checksum
}

bench_expr_bound :: proc(points: []Point, reps: int) -> int {
    checksum := 0
    n := len(points)
    for i in 0..<reps {
        for j in 0..<n {
            idx := (j*7 + i) % n
            point := points[idx]
            x := point.x
            y := point.y
            z := point.z
            w := point.w
            checksum += x
            checksum += y
            checksum += z
            checksum += w
        }
    }
    return checksum
}

main :: proc() {
    fmt.printfln("POINT_N=%v REPS=%v", POINT_N, REPS)
    points := build_points(POINT_N)
    defer delete(points)

    old_allocator := context.allocator
    track := mem.Tracking_Allocator{}
    mem.tracking_allocator_init(&track, old_allocator, old_allocator)
    defer mem.tracking_allocator_destroy(&track)
    context.allocator = mem.tracking_allocator(&track)
    defer context.allocator = old_allocator

    mem.tracking_allocator_reset(&track)
    {
        start := time.tick_now()
        run_one("local-direct", bench_local_direct(points[:], REPS), start, &track)
    }
    mem.tracking_allocator_reset(&track)
    {
        start := time.tick_now()
        run_one("local-bound", bench_local_bound(points[:], REPS), start, &track)
    }
    mem.tracking_allocator_reset(&track)
    {
        start := time.tick_now()
        run_one("expr-direct", bench_expr_direct(points[:], REPS), start, &track)
    }
    mem.tracking_allocator_reset(&track)
    {
        start := time.tick_now()
        run_one("expr-bound", bench_expr_bound(points[:], REPS), start, &track)
    }
}

