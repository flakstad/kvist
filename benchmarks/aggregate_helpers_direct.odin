// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import mem "core:mem"
import slice "core:slice"
import time "core:time"

ORDER_N :: 75_000
ORDER_REPS :: 40

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

settled :: proc(order: Order) -> bool {
    return order.status == 3
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

report_checksum :: proc(rows: []Region_Report) -> int {
    total := 0
    for row in rows {
        total += row.revenue
        total += row.region * 31
        total += row.count
    }
    return total
}

rows_from_aggregates :: proc(revenue_by_region, count_by_region: map[int]int) -> [dynamic]Region_Report {
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

bench_report_group :: proc(orders: []Order, reps: int) -> int {
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
            append(&rows, Region_Report{
                region = region,
                revenue = revenue,
                count = len(group),
            })
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

bench_report_aggregate :: proc(orders: []Order, reps: int) -> int {
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

        revenue_by_region := make(map[int]int)
        for order in work {
            revenue_by_region[order.region] += order.amount
        }
        count_by_region := make(map[int]int)
        for order in work {
            count_by_region[order.region] += 1
        }

        rows := rows_from_aggregates(revenue_by_region, count_by_region)
        checksum += report_checksum(rows[:])
        delete(work)
        delete(revenue_by_region)
        delete(count_by_region)
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
            settled_order := settle_order(order)
            if settled_order.status == 3 {
                revenue_by_region[settled_order.region] += settled_order.amount
                count_by_region[settled_order.region] += 1
            }
        }
        rows := rows_from_aggregates(revenue_by_region, count_by_region)
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
    fmt.printfln("ORDER_N=%v ORDER_REPS=%v", ORDER_N, ORDER_REPS)
    old_allocator := context.allocator
    track: mem.Tracking_Allocator
    orders := make_orders(ORDER_N)
    mem.tracking_allocator_init(&track, old_allocator, old_allocator)
    defer mem.tracking_allocator_destroy(&track)
    defer delete(orders)
    context.allocator = mem.tracking_allocator(&track)
    defer context.allocator = old_allocator

    mem.tracking_allocator_reset(&track)
    start := time.tick_now()
    run_one("report-group", bench_report_group(orders[:], ORDER_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("report-aggregate", bench_report_aggregate(orders[:], ORDER_REPS), start, &track)
    mem.tracking_allocator_reset(&track)
    start = time.tick_now()
    run_one("report-loop", bench_report_loop(orders[:], ORDER_REPS), start, &track)
}
