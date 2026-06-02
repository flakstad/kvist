package main

import "core:fmt"
import mem "core:mem"
import time "core:time"

N :: 50_000
REPS :: 80
SCAN_REPS :: 400
BUILDER_REPS :: 60
REMOVE_REPS :: 300
REORDER_REPS :: 120

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

inc_value :: proc(x: int) -> int { return x + 1 }
even_value_p :: proc(x: int) -> bool { return x % 2 == 0 }
divisible_by_three_p :: proc(x: int) -> bool { return x % 3 == 0 }
add_values :: proc(acc, x: int) -> int { return acc + x }
double :: proc(x: int) -> int { return x * 2 }
always_seven :: proc() -> int { return 7 }
below_cutoff_p :: proc(x: int) -> bool { return x < N / 2 }

make_range :: proc(start, end, step: int) -> [dynamic]int {
    if step == 0 {
        return make([dynamic]int)
    }
    count := 0
    if step > 0 && start < end {
        count = ((end-start-1)/step) + 1
    } else if step < 0 && start > end {
        count = ((start-end-1)/(-step)) + 1
    }
    out := make([dynamic]int, 0, count)
    if step > 0 {
        for i := start; i < end; i += step {
            append(&out, i)
        }
    } else {
        for i := start; i > end; i += step {
            append(&out, i)
        }
    }
    return out
}

bench_pipe_eager :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        mapped := make([dynamic]int, 0, len(xs))
        for x in xs {
            append(&mapped, inc_value(x))
        }
        filtered := make([dynamic]int, 0, len(mapped))
        for x in mapped {
            if even_value_p(x) {
                append(&filtered, x)
            }
        }
        removed := make([dynamic]int, 0, len(filtered))
        for x in filtered {
            if !divisible_by_three_p(x) {
                append(&removed, x)
            }
        }
        total := 0
        for x in removed {
            total = add_values(total, x)
        }
        checksum += total
        delete(removed)
        delete(filtered)
        delete(mapped)
    }
    return checksum
}

bench_pipe_fused :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        total := 0
        for x in xs {
            mapped := inc_value(x)
            if even_value_p(mapped) && !divisible_by_three_p(mapped) {
                total += mapped
            }
        }
        checksum += total
    }
    return checksum
}

bench_builders :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        numbers := make_range(1, N, 1)
        sampled := make([dynamic]int, 0, (len(xs)+3-1)/3)
        for j := 0; j < len(xs); j += 3 {
            append(&sampled, xs[j])
        }
        repeated := make([dynamic]int, 0, 8)
        for j := 0; j < 8; j += 1 {
            append(&repeated, 9)
        }
        generated := make([dynamic]int, 0, 8)
        for j := 0; j < 8; j += 1 {
            append(&generated, always_seven())
        }
        powers := make([dynamic]int, 0, 8)
        current := 1
        for j := 0; j < 8; j += 1 {
            append(&powers, current)
            current = double(current)
        }
        cycled := make([dynamic]int, 0, 9)
        for j := 0; j < 9; j += 1 {
            append(&cycled, xs[j%len(xs)])
        }
        checksum += numbers[len(numbers)-1]
        checksum += sampled[len(sampled)-1]
        checksum += repeated[len(repeated)-1]
        checksum += generated[len(generated)-1]
        checksum += powers[len(powers)-1]
        checksum += cycled[len(cycled)-1]
        delete(cycled)
        delete(powers)
        delete(generated)
        delete(repeated)
        delete(sampled)
        delete(numbers)
    }
    return checksum
}

bench_scan :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        prefix := xs[:]
        for j := 0; j < len(xs); j += 1 {
            x := xs[j]
            if !below_cutoff_p(x) {
                prefix = xs[:j]
                break
            }
        }
        suffix := xs[len(xs):]
        for j := 0; j < len(xs); j += 1 {
            x := xs[j]
            if !below_cutoff_p(x) {
                suffix = xs[j:]
                break
            }
        }
        first_hit := 0
        found := false
        for x in suffix {
            if divisible_by_three_p(x) {
                first_hit = x
                found = true
                break
            }
        }
        any_p := false
        for x in suffix {
            if divisible_by_three_p(x) {
                any_p = true
                break
            }
        }
        all_p := true
        for x in prefix {
            if !below_cutoff_p(x) {
                all_p = false
                break
            }
        }
        checksum += len(prefix)
        checksum += len(suffix)
        if found {
            checksum += first_hit
        }
        if any_p {
            checksum += 1
        }
        if all_p {
            checksum += 1
        }
    }
    return checksum
}

bench_reorder_direct :: proc(xs, ys: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        reversed := make([dynamic]int, 0, len(xs))
        for j := len(xs)-1; j >= 0; j -= 1 {
            append(&reversed, xs[j])
        }

        interposed := make([dynamic]int, 0, max(0, len(xs)*2-1))
        if len(xs) > 0 {
            append(&interposed, xs[0])
            for x in xs[1:] {
                append(&interposed, 0)
                append(&interposed, x)
            }
        }

        n := len(xs)
        if len(ys) < n {
            n = len(ys)
        }
        interleaved := make([dynamic]int, 0, n*2)
        for j := 0; j < n; j += 1 {
            append(&interleaved, xs[j])
            append(&interleaved, ys[j])
        }

        checksum += reversed[0]
        checksum += interposed[1]
        checksum += interleaved[1]
        checksum += len(reversed)
        checksum += len(interposed)
        checksum += len(interleaved)
        delete(interleaved)
        delete(interposed)
        delete(reversed)
    }
    return checksum
}

bench_remove_at_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    mid := len(xs) / 2
    for i := 0; i < reps; i += 1 {
        ordered := make([dynamic]int, 0, len(xs))
        append(&ordered, ..xs)
        ordered_remove(&ordered, mid)

        unordered := make([dynamic]int, 0, len(xs))
        append(&unordered, ..xs)
        unordered_remove(&unordered, mid)

        checksum += len(ordered)
        checksum += ordered[mid]
        checksum += len(unordered)
        checksum += unordered[mid]
        delete(unordered)
        delete(ordered)
    }
    return checksum
}

bench_remove_at_bang_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    mid := len(xs) / 2
    for i := 0; i < reps; i += 1 {
        ordered := make([dynamic]int, 0, len(xs))
        append(&ordered, ..xs)
        unordered := make([dynamic]int, 0, len(xs))
        append(&unordered, ..xs)

        ordered_remove(&ordered, mid)
        unordered_remove(&unordered, mid)

        checksum += len(ordered)
        checksum += ordered[mid]
        checksum += len(unordered)
        checksum += unordered[mid]
        delete(unordered)
        delete(ordered)
    }
    return checksum
}

main :: proc() {
    old_allocator := context.allocator
    xs := make_range(1, N, 1)
    ys := make_range(N, N*2, 1)
    defer delete(xs)
    defer delete(ys)
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, old_allocator, old_allocator)
    defer mem.tracking_allocator_destroy(&track)
    context.allocator = mem.tracking_allocator(&track)
    defer context.allocator = old_allocator

    mem.tracking_allocator_reset(&track)
    start := time.tick_now()
    run_one("pipe-direct", bench_pipe_eager(xs[:], REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("pipe-fused", bench_pipe_fused(xs[:], REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("builders-direct", bench_builders(xs[:], BUILDER_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("scan-direct", bench_scan(xs[:], SCAN_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("reorder-direct", bench_reorder_direct(xs[:], ys[:], REORDER_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("remove-at-direct", bench_remove_at_direct(xs[:], REMOVE_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("remove-at!-direct", bench_remove_at_bang_direct(xs[:], REMOVE_REPS), start, &track)
}
