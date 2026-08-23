// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist_condition

import "core:fmt"

Handler_Entry :: struct {
    kind:    string,
    // Source packages have package-prefixed Condition/Decision names. Keep
    // only the procedure address here; the signalling package casts and
    // invokes it with its ABI-identical public Kvist types.
    handler: rawptr,
}

Rendered_Value :: struct {
    data:   [^]u8,
    length: int,
}

Repl_Push_Handler :: proc "c" (
    ctx: rawptr,
    kind: Rendered_Value,
    handler: rawptr,
)
Repl_Pop_Handler :: proc "c" (ctx: rawptr)
Repl_Handler_Count :: proc "c" (ctx: rawptr) -> int
Repl_Handler_Kind_At :: proc "c" (ctx: rawptr, index: int) -> Rendered_Value
Repl_Handler_At :: proc "c" (ctx: rawptr, index: int) -> rawptr

repl_ctx: rawptr
repl_push_handler: Repl_Push_Handler
repl_pop_handler: Repl_Pop_Handler
repl_handler_count: Repl_Handler_Count
repl_handler_kind_at: Repl_Handler_Kind_At
repl_handler_at: Repl_Handler_At

set_repl_host :: proc(
    ctx: rawptr,
    push: Repl_Push_Handler,
    pop: Repl_Pop_Handler,
    count: Repl_Handler_Count,
    kind_at: Repl_Handler_Kind_At,
    at: Repl_Handler_At,
) {
    repl_ctx = ctx
    repl_push_handler = push
    repl_pop_handler = pop
    repl_handler_count = count
    repl_handler_kind_at = kind_at
    repl_handler_at = at
}

MAX_HANDLER_DEPTH :: 64

@(thread_local)
handler_stack: [MAX_HANDLER_DEPTH]Handler_Entry

@(thread_local)
current_handler_count: int

push_handler :: proc(kind: string, handler: rawptr) {
    if repl_push_handler != nil {
        repl_push_handler(repl_ctx, Rendered_Value{
            data = raw_data(kind),
            length = len(kind),
        }, handler)
        return
    }
    assert(handler != nil, "condition handler must not be nil")
    assert(current_handler_count < MAX_HANDLER_DEPTH, "condition handler stack exhausted")
    handler_stack[current_handler_count] = Handler_Entry{kind = kind, handler = handler}
    current_handler_count += 1
}

pop_handler :: proc() {
    if repl_pop_handler != nil {
        repl_pop_handler(repl_ctx)
        return
    }
    assert(current_handler_count > 0, "condition handler stack underflow")
    current_handler_count -= 1
    handler_stack[current_handler_count] = {}
}

handler_count :: proc() -> int {
    if repl_handler_count != nil {
        return repl_handler_count(repl_ctx)
    }
    return current_handler_count
}

handler_kind_at :: proc(index: int) -> string {
    if repl_handler_kind_at != nil {
        value := repl_handler_kind_at(repl_ctx, index)
        return string(value.data[:value.length])
    }
    assert(index >= 0 && index < current_handler_count)
    return handler_stack[index].kind
}

handler_at :: proc(index: int) -> rawptr {
    if repl_handler_at != nil {
        return repl_handler_at(repl_ctx, index)
    }
    assert(index >= 0 && index < current_handler_count)
    return handler_stack[index].handler
}

unhandled :: proc(kind, message: string) {
    panic(fmt.tprintf("unhandled condition %s: %s", kind, message))
}
