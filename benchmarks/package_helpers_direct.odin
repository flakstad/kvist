// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

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

build_map_keys :: proc() -> [dynamic]int {
    out := make([dynamic]int, 0, 4)
    append(&out, 1)
    append(&out, 2)
    append(&out, 3)
    append(&out, 4)
    return out
}

build_map_vals :: proc() -> [dynamic]int {
    out := make([dynamic]int, 0, 4)
    append(&out, 10)
    append(&out, 20)
    append(&out, 30)
    append(&out, 40)
    return out
}

build_set_rhs :: proc() -> map[int]struct{} {
    out := make(map[int]struct{}, 5)
    out[4] = {}
    out[5] = {}
    out[6] = {}
    out[7] = {}
    out[8] = {}
    return out
}

build_set_mutable :: proc() -> map[int]struct{} {
    out := make(map[int]struct{}, 6)
    out[1] = {}
    out[2] = {}
    out[3] = {}
    out[4] = {}
    out[5] = {}
    out[6] = {}
    return out
}

build_even_set :: proc() -> map[int]struct{} {
    out := make(map[int]struct{}, 5)
    out[2] = {}
    out[4] = {}
    out[6] = {}
    out[8] = {}
    out[10] = {}
    return out
}

bench_str_direct :: proc(reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        source := "  Kvist,odin,core,odin  "
        trimmed := strings.trim_space(source)
        parts := strings.split(trimmed, ",")
        joined, _ := strings.join(parts[:], "-")
        replaced, _ := strings.replace(joined, "odin", "ODIN", 1, context.allocator)
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

bench_map_pure_direct :: proc(reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        base := build_map_mutable()
        overrides := build_map_overrides()
        ks_source := build_map_keys()
        vs_source := build_map_vals()

        associated := make(map[int]int, len(base)+1)
        for key, value in base {
            associated[key] = value
        }
        associated[COUNT] = 99

        dissociated := make(map[int]int, len(associated))
        for key, value in associated {
            if key != 0 {
                dissociated[key] = value
            }
        }

        merged := make(map[int]int, len(base)+len(overrides))
        for key, value in base {
            merged[key] = value
        }
        for key, value in overrides {
            merged[key] = value
        }

        keys := make([dynamic]int, 0, len(merged))
        for key in merged {
            append(&keys, key)
        }

        vals := make([dynamic]int, 0, len(merged))
        for _, value in merged {
            append(&vals, value)
        }

        n := len(ks_source)
        if len(vs_source) < n {
            n = len(vs_source)
        }
        zipped := make(map[int]int, n)
        for j := 0; j < n; j += 1 {
            zipped[ks_source[j]] = vs_source[j]
        }

        checksum += len(associated)
        checksum += len(dissociated)
        checksum += len(merged)
        checksum += len(keys)
        checksum += len(vals)
        checksum += dissociated[COUNT]
        checksum += merged[4]
        checksum += zipped[3]
        if 4 in zipped {
            checksum += 1
        }

        delete(zipped)
        delete(vals)
        delete(keys)
        delete(merged)
        delete(dissociated)
        delete(associated)
        delete(vs_source)
        delete(ks_source)
        delete(overrides)
        delete(base)
    }
    return checksum
}

bench_set_direct :: proc(reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        rhs := build_set_rhs()
        mutable := build_set_mutable()
        evens := build_even_set()
        removed := make(map[int]struct{}, 1)
        removed[2] = {}

        mutable[COUNT+1] = {}
        delete_key(&mutable, 0)
        for value in rhs {
            mutable[value] = {}
        }
        for value in mutable {
            if !(value in evens) {
                delete_key(&mutable, value)
            }
        }
        for value in removed {
            delete_key(&mutable, value)
        }

        checksum += 3
        if 4 in mutable {
            checksum += 1
        }
        if 6 in mutable {
            checksum += 1
        }
        if 8 in mutable {
            checksum += 1
        }

        delete(removed)
        delete(evens)
        delete(mutable)
        delete(rhs)
    }
    return checksum
}

bench_set_pure_direct :: proc(reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        lhs := build_set_mutable()
        rhs := build_set_rhs()

        unioned := make(map[int]struct{}, len(lhs)+len(rhs))
        for value in lhs {
            unioned[value] = {}
        }
        for value in rhs {
            unioned[value] = {}
        }

        cap := len(lhs)
        if len(rhs) < cap {
            cap = len(rhs)
        }
        intersected := make(map[int]struct{}, cap)
        scan := lhs
        probe := rhs
        if len(lhs) > len(rhs) {
            scan = rhs
            probe = lhs
        }
        for value in scan {
            if value in probe {
                intersected[value] = {}
            }
        }

        differed := make(map[int]struct{}, len(lhs))
        for value in lhs {
            if !(value in rhs) {
                differed[value] = {}
            }
        }

        added := make(map[int]struct{}, len(lhs)+1)
        for value in lhs {
            added[value] = {}
        }
        added[COUNT+1] = {}

        removed := make(map[int]struct{}, len(added))
        for value in added {
            if value != 2 {
                removed[value] = {}
            }
        }

        checksum += len(unioned)
        checksum += len(intersected)
        checksum += len(differed)
        checksum += len(removed)
        if 8 in unioned {
            checksum += 1
        }
        subset := true
        if len(intersected) > len(unioned) {
            subset = false
        } else {
            for value in intersected {
                if !(value in unioned) {
                    subset = false
                    break
                }
            }
        }
        if subset {
            checksum += 1
        }
        superset := true
        if len(unioned) < len(intersected) {
            superset = false
        } else {
            for value in intersected {
                if !(value in unioned) {
                    superset = false
                    break
                }
            }
        }
        if superset {
            checksum += 1
        }
        disjoint := true
        scan_disjoint := differed
        probe_disjoint := rhs
        if len(differed) > len(rhs) {
            scan_disjoint = rhs
            probe_disjoint = differed
        }
        for value in scan_disjoint {
            if value in probe_disjoint {
                disjoint = false
                break
            }
        }
        if disjoint {
            checksum += 1
        }

        delete(removed)
        delete(added)
        delete(differed)
        delete(intersected)
        delete(unioned)
        delete(rhs)
        delete(lhs)
    }
    return checksum
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
    run_one("map-pure-direct", bench_map_pure_direct(REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("set-direct", bench_set_direct(REPS), start, &track)

    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("set-pure-direct", bench_set_pure_direct(REPS), start, &track)
}
