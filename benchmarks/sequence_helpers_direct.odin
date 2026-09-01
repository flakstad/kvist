package main

import "core:fmt"
import mem "core:mem"
import slice "core:slice"
import time "core:time"

N :: 50_000
REPS :: 80
SORT_N :: 5_000
SORT_REPS :: 5
ORDER_N :: 75_000
ORDER_REPS :: 40

Sort_Item :: struct {
    value: int,
    score: int,
}

Order :: struct {
    account: int,
    amount: int,
    discount: int,
    status: int,
    region: int,
}

Region_Report :: struct {
    region: int,
    revenue: int,
    count: int,
}

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

make_range :: proc(start, end: int) -> [dynamic]int {
    count := end - start
    if count <= 0 {
        return make([dynamic]int)
    }
    out := make([dynamic]int, 0, count)
    for i := start; i < end; i += 1 {
        append(&out, i)
    }
    return out
}

make_sort_items :: proc(n: int) -> [dynamic]Sort_Item {
    out := make([dynamic]Sort_Item, 0, n)
    for i in 0..<n {
        append(&out, Sort_Item{value = i, score = n-i})
    }
    return out
}

make_orders :: proc(n: int) -> [dynamic]Order {
    out := make([dynamic]Order, 0, n)
    for i in 0..<n {
        append(&out, Order{
            account = i % 4096,
            amount = 25 + (i*37)%1500,
            discount = (i*11)%90,
            status = i % 5,
            region = i % 12,
        })
    }
    return out
}

settle_order :: proc(order: Order) -> Order {
    updated := order
    if updated.status == 2 && updated.amount > 500 {
        updated.amount = updated.amount - updated.discount
        updated.discount = 0
        updated.status = 3
    }
    return updated
}

settle_order_ptr :: proc(order: ^Order) {
    if order.status == 2 && order.amount > 500 {
        order.amount = order.amount - order.discount
        order.discount = 0
        order.status = 3
    }
}

orders_checksum :: proc(orders: []Order) -> int {
    total := 0
    for order in orders {
        total += order.amount
        total += order.status
    }
    return total
}

report_checksum :: proc(rows: []Region_Report) -> int {
    total := 0
    for row in rows {
        total += row.revenue
        total += row.region * 31
        total += row.count
    }
    return total
}

build_report_rows :: proc(revenue_by_region, count_by_region: map[int]int) -> [dynamic]Region_Report {
    rows := make([dynamic]Region_Report)
    for region, revenue in revenue_by_region {
        append(&rows, Region_Report{
            region = region,
            revenue = revenue,
            count = count_by_region[region],
        })
    }
    slice.sort_by(rows[:], proc(a, b: Region_Report) -> bool {
        return a.revenue < b.revenue
    })
    return rows
}

bench_range :: proc(reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        xs := make_range(0, N)
        checksum += xs[len(xs)-1]
        delete(xs)
    }
    return checksum
}

bench_map :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        mapped := make([dynamic]int, 0, len(xs))
        for x in xs {
            append(&mapped, x+1)
        }
        checksum += mapped[len(mapped)-1]
        delete(mapped)
    }
    return checksum
}

bench_filter :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        filtered := make([dynamic]int, 0, len(xs))
        for x in xs {
            if x%2 == 0 {
                append(&filtered, x)
            }
        }
        checksum += len(filtered)
        delete(filtered)
    }
    return checksum
}

bench_take_nth :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        sampled := make([dynamic]int, 0, (len(xs)+3-1)/3)
        for j := 0; j < len(xs); j += 3 {
            append(&sampled, xs[j])
        }
        checksum += sampled[len(sampled)-1]
        delete(sampled)
    }
    return checksum
}

bench_partition_all :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        chunks := make([dynamic][]int, 0, (len(xs)+8-1)/8)
        for start := 0; start < len(xs); start += 8 {
            end := start + 8
            if end > len(xs) {
                end = len(xs)
            }
            append(&chunks, xs[start:end])
        }
        checksum += len(chunks)
        delete(chunks)
    }
    return checksum
}

bench_distinct :: proc(xs: []int, reps: int) -> int {
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
        delete(seen)
        delete(unique)
    }
    return checksum
}

bench_zipmap :: proc(keys, values: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        limit := len(keys)
        if limit > len(values) {
            limit = len(values)
        }
        lookup := make(map[int]int, limit)
        for j := 0; j < limit; j += 1 {
            lookup[keys[j]] = values[j]
        }
        checksum += len(lookup)
        delete(lookup)
    }
    return checksum
}

bench_frequencies :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        counts := make(map[int]int, len(xs))
        for x in xs {
            counts[x] += 1
        }
        checksum += counts[1024]
        delete(counts)
    }
    return checksum
}

bench_index_by :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        indexed := make(map[int]int, len(xs))
        for x in xs {
            indexed[x] = x
        }
        checksum += len(indexed)
        delete(indexed)
    }
    return checksum
}

bench_group_by :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        groups := make(map[int][dynamic]int)
        for x in xs {
            key := x % 1024
            group := groups[key]
            append(&group, x)
            if len(group) == 8 {
                reserve(&group, 64)
            }
            groups[key] = group
        }
        checksum += len(groups)
        for _, group in groups {
            delete(group)
        }
        delete(groups)
    }
    return checksum
}

bench_merge :: proc(lhs, rhs: map[int]int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        merged := make(map[int]int, len(lhs)+len(rhs))
        for key, value in lhs {
            merged[key] = value
        }
        for key, value in rhs {
            merged[key] = value
        }
        checksum += len(merged)
        delete(merged)
    }
    return checksum
}

bench_sort :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        sorted := make([dynamic]int, 0, len(xs))
        append(&sorted, ..xs)
        slice.sort(sorted[:])
        checksum += sorted[0]
        delete(sorted)
    }
    return checksum
}

bench_sort_by :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        sorted := make([dynamic]int, 0, len(xs))
        append(&sorted, ..xs)
        slice.sort_by(sorted[:], proc(a, b: int) -> bool {
            return -a < -b
        })
        checksum += sorted[0]
        delete(sorted)
    }
    return checksum
}

bench_sort_by_field :: proc(xs: []Sort_Item, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        sorted := make([dynamic]Sort_Item, 0, len(xs))
        append(&sorted, ..xs)
        slice.sort_by(sorted[:], proc(a, b: Sort_Item) -> bool {
            return a.score < b.score
        })
        checksum += sorted[0].value
        delete(sorted)
    }
    return checksum
}

bench_pipeline_map_filter_reduce :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        total := 0
        for x in xs {
            y := x + 1
            if y%2 == 0 {
                total += y
            }
        }
        checksum += total
    }
    return checksum
}

bench_pipeline_threaded :: proc(xs: []int, reps: int) -> int {
    return bench_pipeline_map_filter_reduce(xs, reps)
}

bench_pipeline_loop :: proc(xs: []int, reps: int) -> int {
    return bench_pipeline_map_filter_reduce(xs, reps)
}

bench_pipeline_bang_copy :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        work := make([dynamic]int, 0, len(xs))
        for x in xs {
            append(&work, x+1)
        }
        write := 0
        for x in work {
            if x%2 == 0 {
                work[write] = x
                write += 1
            }
        }
        resize(&work, write)
        total := 0
        for x in work {
            total += x
        }
        checksum += total
        delete(work)
    }
    return checksum
}

bench_pipeline_filter_map_take :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        total := 0
        taken := 0
        for x in xs {
            if x%3 == 0 {
                total += x * 3
                taken += 1
                if taken == 100 {
                    break
                }
            }
        }
        checksum += total
    }
    return checksum
}

bench_pipeline_filter_map_take_loop :: proc(xs: []int, reps: int) -> int {
    return bench_pipeline_filter_map_take(xs, reps)
}

bench_pipeline_sort_map :: proc(xs: []int, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        sorted := make([dynamic]int, 0, len(xs))
        append(&sorted, ..xs)
        slice.sort(sorted[:])
        checksum += sorted[0] + 1
        delete(sorted)
    }
    return checksum
}

bench_pipeline_sort_loop :: proc(xs: []int, reps: int) -> int {
    return bench_pipeline_sort_map(xs, reps)
}

bench_orders_revenue :: proc(orders: []Order, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        total := 0
        for order in orders {
            if order.status == 2 && order.amount > 500 {
                total += order.amount - order.discount
            }
        }
        checksum += total
    }
    return checksum
}

bench_orders_revenue_threaded :: proc(orders: []Order, reps: int) -> int {
    return bench_orders_revenue(orders, reps)
}

bench_orders_revenue_loop :: proc(orders: []Order, reps: int) -> int {
    return bench_orders_revenue(orders, reps)
}

bench_orders_update_map_bang :: proc(orders: []Order, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        for j in 0..<len(orders) {
            orders[j] = settle_order(orders[j])
        }
        checksum += orders_checksum(orders)
    }
    return checksum
}

bench_orders_update_filter_bang :: proc(orders: []Order, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        work := make([dynamic]Order, 0, len(orders))
        for order in orders {
            append(&work, settle_order(order))
        }
        write := 0
        for order in work {
            if order.status == 3 {
                work[write] = order
                write += 1
            }
        }
        resize(&work, write)
        checksum += orders_checksum(work[:])
        delete(work)
    }
    return checksum
}

bench_orders_update_pointer_loop :: proc(orders: []Order, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        for j in 0..<len(orders) {
            settle_order_ptr(&orders[j])
        }
        checksum += orders_checksum(orders)
    }
    return checksum
}

bench_report_eager :: proc(orders: []Order, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        settled := make([dynamic]Order, 0, len(orders))
        for order in orders {
            append(&settled, settle_order(order))
        }
        paid := make([dynamic]Order, 0, len(settled))
        for order in settled {
            if order.status == 3 {
                append(&paid, order)
            }
        }
        groups := make(map[int][dynamic]Order)
        for order in paid {
            group := groups[order.region]
            append(&group, order)
            if len(group) == 8 {
                reserve(&group, 64)
            }
            groups[order.region] = group
        }
        rows := make([dynamic]Region_Report)
        for region, group in groups {
            revenue := 0
            for order in group {
                revenue += order.amount
            }
            append(&rows, Region_Report{region = region, revenue = revenue, count = len(group)})
        }
        slice.sort_by(rows[:], proc(a, b: Region_Report) -> bool {
            return a.revenue < b.revenue
        })
        checksum += report_checksum(rows[:])
        delete(settled)
        delete(paid)
        for _, group in groups {
            delete(group)
        }
        delete(groups)
        delete(rows)
    }
    return checksum
}

bench_report_bang :: proc(orders: []Order, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        work := make([dynamic]Order, 0, len(orders))
        for order in orders {
            append(&work, settle_order(order))
        }
        write := 0
        for order in work {
            if order.status == 3 {
                work[write] = order
                write += 1
            }
        }
        resize(&work, write)
        groups := make(map[int][dynamic]Order)
        for order in work {
            group := groups[order.region]
            append(&group, order)
            if len(group) == 8 {
                reserve(&group, 64)
            }
            groups[order.region] = group
        }
        rows := make([dynamic]Region_Report)
        for region, group in groups {
            revenue := 0
            for order in group {
                revenue += order.amount
            }
            append(&rows, Region_Report{region = region, revenue = revenue, count = len(group)})
        }
        slice.sort_by(rows[:], proc(a, b: Region_Report) -> bool {
            return a.revenue < b.revenue
        })
        checksum += report_checksum(rows[:])
        delete(work)
        for _, group in groups {
            delete(group)
        }
        delete(groups)
        delete(rows)
    }
    return checksum
}

bench_report_loop :: proc(orders: []Order, reps: int) -> int {
    checksum := 0
    for i := 0; i < reps; i += 1 {
        revenue_by_region := make(map[int]int)
        count_by_region := make(map[int]int)
        for order in orders {
            settled := settle_order(order)
            if settled.status == 3 {
                revenue_by_region[settled.region] += settled.amount
                count_by_region[settled.region] += 1
            }
        }
        rows := build_report_rows(revenue_by_region, count_by_region)
        checksum += report_checksum(rows[:])
        delete(rows)
        delete(revenue_by_region)
        delete(count_by_region)
    }
    return checksum
}

run_one :: proc(name: string, checksum: int, start: time.Tick, track: ^mem.Tracking_Allocator) {
    report(name, time.tick_since(start), checksum, track)
}

main :: proc() {
    fmt.printfln(
        "N=%v REPS=%v SORT_N=%v SORT_REPS=%v ORDER_N=%v ORDER_REPS=%v",
        N,
        REPS,
        SORT_N,
        SORT_REPS,
        ORDER_N,
        ORDER_REPS,
    )
    old_allocator := context.allocator
    track: mem.Tracking_Allocator
    xs := make_range(0, N)
    ys := make_range(N, N*2)
    sort_base := make_range(0, SORT_N)
    sort_xs := make([dynamic]int, 0, len(sort_base))
    for i := len(sort_base)-1; i >= 0; i -= 1 {
        append(&sort_xs, sort_base[i])
    }
    sort_items := make_sort_items(SORT_N)
    orders := make_orders(ORDER_N)
    orders_map := make_orders(ORDER_N)
    orders_filter := make_orders(ORDER_N)
    orders_ptr := make_orders(ORDER_N)
    lhs := make(map[int]int, len(xs))
    rhs := make(map[int]int, len(ys))
    for x in xs {
        lhs[x] = x
    }
    for y in ys {
        rhs[y] = y
    }
    mem.tracking_allocator_init(&track, old_allocator, old_allocator)
    defer mem.tracking_allocator_destroy(&track)
    defer {
        delete(xs)
        delete(ys)
        delete(sort_base)
        delete(sort_xs)
        delete(sort_items)
        delete(orders)
        delete(orders_map)
        delete(orders_filter)
        delete(orders_ptr)
        delete(lhs)
        delete(rhs)
    }
    context.allocator = mem.tracking_allocator(&track)
    defer context.allocator = old_allocator

    mem.tracking_allocator_reset(&track)
    start := time.tick_now()
    run_one("range", bench_range(REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("map", bench_map(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("filter", bench_filter(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("take-nth", bench_take_nth(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("partition-all", bench_partition_all(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("distinct", bench_distinct(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("zipmap", bench_zipmap(xs[:], ys[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("frequencies", bench_frequencies(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("index-by", bench_index_by(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("group-by", bench_group_by(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("merge", bench_merge(lhs, rhs, REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("sort", bench_sort(sort_xs[:], SORT_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("sort-by", bench_sort_by(sort_base[:], SORT_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("sort-by-field", bench_sort_by_field(sort_items[:], SORT_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("pipe-map-filter", bench_pipeline_map_filter_reduce(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("pipe-threaded", bench_pipeline_threaded(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("pipe-loop", bench_pipeline_loop(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("pipe-bang-copy", bench_pipeline_bang_copy(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("pipe-filter-map", bench_pipeline_filter_map_take(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("pipe-filter-loop", bench_pipeline_filter_map_take_loop(xs[:], REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("pipe-sort-map", bench_pipeline_sort_map(sort_xs[:], SORT_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("pipe-sort-loop", bench_pipeline_sort_loop(sort_xs[:], SORT_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("orders-revenue", bench_orders_revenue(orders[:], ORDER_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("orders-threaded", bench_orders_revenue_threaded(orders[:], ORDER_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("orders-loop", bench_orders_revenue_loop(orders[:], ORDER_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("orders-map!", bench_orders_update_map_bang(orders_map[:], ORDER_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("orders-filter!", bench_orders_update_filter_bang(orders_filter[:], ORDER_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("orders-ptr-loop", bench_orders_update_pointer_loop(orders_ptr[:], ORDER_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("report-eager", bench_report_eager(orders[:], ORDER_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("report-bang", bench_report_bang(orders[:], ORDER_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("report-loop", bench_report_loop(orders[:], ORDER_REPS), start, &track)
}
