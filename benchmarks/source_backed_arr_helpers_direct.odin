// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import mem "core:mem"
import "core:slice"
import time "core:time"

N :: 50_000
REPS :: 80
SCAN_REPS :: 400
BUILDER_REPS :: 60
KEEP_REPS :: 220
MAP_BANG_REPS :: 220
FILTER_BANG_REPS :: 220
KEEP_BANG_REPS :: 220
REMOVE_REPS :: 300
REORDER_REPS :: 120
PARTITION_REPS :: 300
PARTITION_BY_REPS :: 120
FREQUENCIES_REPS :: 220
INDEX_BY_REPS :: 220
GROUP_BY_REPS :: 120
COUNT_BY_REPS :: 220
SUM_BY_REPS :: 220
DISTINCT_REPS :: 120
DISTINCT_BY_REPS :: 220
SORT_REPS :: 80
SHUFFLE_REPS :: 160

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
parity :: proc(x: int) -> int { return x % 2 }
add_values :: proc(acc, x: int) -> int { return acc + x }
double :: proc(x: int) -> int { return x * 2 }
always_seven :: proc() -> int { return 7 }
pick_first :: proc(n: int) -> int { return 0 }
below_cutoff_p :: proc(x: int) -> bool { return x < N / 2 }

keep_even :: proc(x: int) -> (value: int, ok: bool) {
    if even_value_p(x) {
        return x, true
    }
    return 0, false
}

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

bench_keep_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        kept := make([dynamic]int, 0, len(xs))
        for x in xs {
            value, ok := keep_even(x)
            if ok {
                append(&kept, value)
            }
        }
        checksum += len(kept)
        checksum += kept[0]
        checksum += kept[len(kept)-1]
        delete(kept)
    }
    return checksum
}

bench_map_bang_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        mutable := make([dynamic]int, 0, len(xs))
        append(&mutable, ..xs)
        for j in 0..<len(mutable) {
            mutable[j] = inc_value(mutable[j])
        }
        checksum += mutable[0]
        checksum += mutable[len(mutable)-1]
        delete(mutable)
    }
    return checksum
}

bench_filter_bang_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        mutable := make([dynamic]int, 0, len(xs))
        append(&mutable, ..xs)
        write := 0
        for x in mutable {
            if even_value_p(x) {
                mutable[write] = x
                write += 1
            }
        }
        resize(&mutable, write)
        checksum += len(mutable)
        checksum += mutable[0]
        checksum += mutable[len(mutable)-1]
        delete(mutable)
    }
    return checksum
}

bench_remove_bang_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        mutable := make([dynamic]int, 0, len(xs))
        append(&mutable, ..xs)
        write := 0
        for x in mutable {
            if !even_value_p(x) {
                mutable[write] = x
                write += 1
            }
        }
        resize(&mutable, write)
        checksum += len(mutable)
        checksum += mutable[0]
        checksum += mutable[len(mutable)-1]
        delete(mutable)
    }
    return checksum
}

bench_keep_bang_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        mutable := make([dynamic]int, 0, len(xs))
        append(&mutable, ..xs)
        write := 0
        for x in mutable {
            value, ok := keep_even(x)
            if ok {
                mutable[write] = value
                write += 1
            }
        }
        resize(&mutable, write)
        checksum += len(mutable)
        checksum += mutable[0]
        checksum += mutable[len(mutable)-1]
        delete(mutable)
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

bench_partition_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        chunks := make([dynamic][]int, 0, len(xs)/64)
        for start := 0; start+64 <= len(xs); start += 64 {
            append(&chunks, xs[start:start+64])
        }

        chunks_all := make([dynamic][]int, 0, (len(xs)+64-1)/64)
        for start := 0; start < len(xs); start += 64 {
            end := start + 64
            if end > len(xs) {
                end = len(xs)
            }
            append(&chunks_all, xs[start:end])
        }

        checksum += len(chunks)
        checksum += len(chunks_all)
        checksum += len(chunks[0])
        checksum += len(chunks_all[len(chunks_all)-1])
        delete(chunks_all)
        delete(chunks)
    }
    return checksum
}

bench_partition_by_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        if len(xs) == 0 {
            continue
        }
        groups := make([dynamic][]int, 0, len(xs))
        start := 0
        last_key := parity(xs[0])
        for j := 1; j < len(xs); j += 1 {
            key := parity(xs[j])
            if key != last_key {
                append(&groups, xs[start:j])
                start = j
                last_key = key
            }
        }
        append(&groups, xs[start:])
        checksum += len(groups)
        checksum += len(groups[0])
        checksum += len(groups[len(groups)-1])
        delete(groups)
    }
    return checksum
}

bench_frequencies_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        counts := make(map[int]int, len(xs))
        for x in xs {
            counts[x] += 1
        }
        checksum += len(counts)
        checksum += counts[1]
        delete(counts)
    }
    return checksum
}

bench_index_by_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        indexed := make(map[int]int, len(xs))
        for x in xs {
            indexed[parity(x)] = x
        }
        checksum += len(indexed)
        checksum += indexed[0]
        checksum += indexed[1]
        delete(indexed)
    }
    return checksum
}

bench_group_by_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        groups := make(map[int][dynamic]int)
        for x in xs {
            key := parity(x)
            group := groups[key]
            append(&group, x)
            if len(group) == 8 {
                reserve(&group, 64)
            }
            groups[key] = group
        }
        checksum += len(groups)
        checksum += len(groups[0])
        checksum += len(groups[1])
        for _, group in groups {
            delete(group)
        }
        delete(groups)
    }
    return checksum
}

bench_count_by_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        counts := make(map[int]int)
        for x in xs {
            counts[parity(x)] += 1
        }
        checksum += len(counts)
        checksum += counts[0]
        checksum += counts[1]
        delete(counts)
    }
    return checksum
}

bench_sum_by_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        sums := make(map[int]int)
        for x in xs {
            sums[parity(x)] += inc_value(x)
        }
        checksum += len(sums)
        checksum += sums[0]
        checksum += sums[1]
        delete(sums)
    }
    return checksum
}

bench_distinct_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        unique := make([dynamic]int, 0, len(xs))
        seen := make(map[int]bool, len(xs))
        for x in xs {
            if seen[x] {
                continue
            }
            seen[x] = true
            append(&unique, x)
        }
        checksum += len(unique)
        checksum += unique[0]
        checksum += unique[len(unique)-1]
        delete(seen)
        delete(unique)
    }
    return checksum
}

bench_distinct_by_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        unique := make([dynamic]int, 0, len(xs))
        seen := make(map[int]bool, len(xs))
        for x in xs {
            key := parity(x)
            if seen[key] {
                continue
            }
            seen[key] = true
            append(&unique, x)
        }
        checksum += len(unique)
        checksum += unique[0]
        checksum += unique[len(unique)-1]
        delete(seen)
        delete(unique)
    }
    return checksum
}

bench_sort_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        sorted := make([dynamic]int, 0, len(xs))
        append(&sorted, ..xs)
        slice.sort(sorted[:])

        mutable := make([dynamic]int, 0, len(xs))
        append(&mutable, ..xs)
        slice.sort(mutable[:])

        checksum += sorted[0]
        checksum += sorted[len(sorted)-1]
        checksum += mutable[0]
        checksum += mutable[len(mutable)-1]
        delete(mutable)
        delete(sorted)
    }
    return checksum
}

bench_shuffle_direct :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        shuffled := make([dynamic]int, 0, len(xs))
        append(&shuffled, ..xs)
        for j := len(shuffled)-1; j > 0; j -= 1 {
            k := pick_first(j+1)
            shuffled[j], shuffled[k] = shuffled[k], shuffled[j]
        }

        mutable := make([dynamic]int, 0, len(xs))
        append(&mutable, ..xs)
        for j := len(mutable)-1; j > 0; j -= 1 {
            k := pick_first(j+1)
            mutable[j], mutable[k] = mutable[k], mutable[j]
        }

        checksum += shuffled[0]
        checksum += shuffled[len(shuffled)-1]
        checksum += mutable[0]
        checksum += mutable[len(mutable)-1]
        delete(mutable)
        delete(shuffled)
    }
    return checksum
}

main :: proc() {
    old_allocator := context.allocator
    xs := make_range(1, N, 1)
    ys := make_range(N, N*2, 1)
    reversed := make([dynamic]int, 0, len(xs))
    for i := len(xs)-1; i >= 0; i -= 1 {
        append(&reversed, xs[i])
    }
    defer delete(xs)
    defer delete(ys)
    defer delete(reversed)
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
    run_one("keep-direct", bench_keep_direct(xs[:], KEEP_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("map!-direct", bench_map_bang_direct(xs[:], MAP_BANG_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("filter!-direct", bench_filter_bang_direct(xs[:], FILTER_BANG_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("remove!-direct", bench_remove_bang_direct(xs[:], FILTER_BANG_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("keep!-direct", bench_keep_bang_direct(xs[:], KEEP_BANG_REPS), start, &track)

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

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("partition-direct", bench_partition_direct(xs[:], PARTITION_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("partition-by-direct", bench_partition_by_direct(xs[:], PARTITION_BY_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("freq-direct", bench_frequencies_direct(xs[:], FREQUENCIES_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("index-by-direct", bench_index_by_direct(xs[:], INDEX_BY_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("group-by-direct", bench_group_by_direct(xs[:], GROUP_BY_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("count-by-direct", bench_count_by_direct(xs[:], COUNT_BY_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("sum-by-direct", bench_sum_by_direct(xs[:], SUM_BY_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("distinct-direct", bench_distinct_direct(xs[:], DISTINCT_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("distinct-by-direct", bench_distinct_by_direct(xs[:], DISTINCT_BY_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("sort-direct", bench_sort_direct(reversed[:], SORT_REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("shuffle-direct", bench_shuffle_direct(xs[:], SHUFFLE_REPS), start, &track)
}
