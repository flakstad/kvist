package kvist_repl

import "core:dynlib"
import "core:bufio"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "base:runtime"
import "core:strings"
import "core:sync"
import "core:time"
import repl_plan "../kvist_repl_plan"

GENERATION_ABI_VERSION :: u32(30)

DEBUG_FLAG_PAUSE :: u32(1)
DEBUG_FLAG_TRACE :: u32(2)
DEBUG_FLAG_TRACE_VALUES :: u32(4)
TRACE_LIMIT_MARKER :: "KVIST_REPL_TRACE_LIMIT"
TRACE_END_MARKER :: "KVIST_REPL_TRACE_END"
TRACE_VALUES_LIMIT_MARKER :: "KVIST_REPL_TRACE_VALUES_LIMIT"

Register_Proc :: proc "c" (
    ctx: rawptr,
    name: cstring,
    signature: cstring,
    address: rawptr,
)

Lookup_Proc :: proc "c" (
    ctx: rawptr,
    name: cstring,
    signature: cstring,
) -> rawptr

Register_Result :: proc "c" (
    ctx: rawptr,
    signature: cstring,
    address: rawptr,
)

Stabilize_Result :: proc "c" (
    occupied: [^]rawptr,
    occupied_count: int,
) -> rawptr

Render_Scalar_Result :: proc "c" (
    ctx: rawptr,
    type_name: cstring,
    address: rawptr,
)

Scalar_Value_Kind :: enum u32 {
    Invalid,
    Bool,
    Int,
    F64,
    String,
    Data,
}

Rendered_Value :: struct {
    data:   [^]u8,
    length: int,
}

Scalar_Managed_Release :: proc "c" (ctx: rawptr)
Scalar_Managed_Commit :: proc "c" (ctx: rawptr) -> rawptr
Scalar_Managed_Render :: proc "c" (
    ctx: rawptr,
    rendered: ^Rendered_Value,
) -> bool

Scalar_Value :: struct {
    kind:          Scalar_Value_Kind,
    owned:         bool,
    int_value:     i64,
    float_value:   f64,
    string_data:   [^]u8,
    string_length: int,
    source_address: rawptr,
    result_address: rawptr,
    source_value: rawptr,
    managed_context: rawptr,
    managed_release: Scalar_Managed_Release,
    managed_commit: Scalar_Managed_Commit,
    managed_render: Scalar_Managed_Render,
}

Scalar_Invoke :: proc "c" (
    args: [^]Scalar_Value,
    arg_count: int,
    result: ^Scalar_Value,
) -> bool

Register_Scalar_Invoke :: proc "c" (
    ctx: rawptr,
    name: cstring,
    signature: cstring,
    result_abi: cstring,
    address: Scalar_Invoke,
)

State_Clone :: proc "c" (snapshot: rawptr)
State_Restore :: proc "c" (snapshot: rawptr)

Register_State :: proc "c" (
    ctx: rawptr,
    name: cstring,
    signature: cstring,
    size,
    align: int,
    clone: State_Clone,
    restore: State_Restore,
)

Page_Emit :: proc "c" (
    ctx: rawptr,
    index: int,
    key: Rendered_Value,
    value: Rendered_Value,
)

Collection_Emit :: proc "c" (
    ctx: rawptr,
    relative_path: Rendered_Value,
    shape: Rendered_Value,
    element_type: Rendered_Value,
    key_type: Rendered_Value,
    value_type: Rendered_Value,
    collection_ctx: rawptr,
    render_page: rawptr,
    copy_context_size: int,
    copy_context_align: int,
)

Render_Page :: proc "c" (
    collection_ctx: rawptr,
    offset,
    limit: int,
    emit_ctx: rawptr,
    emit: Page_Emit,
    emit_collection: Collection_Emit,
) -> int

Debug_Collection :: struct {
    path:          Rendered_Value,
    shape:         Rendered_Value,
    element_type: Rendered_Value,
    key_type:      Rendered_Value,
    value_type:    Rendered_Value,
    collection_ctx: rawptr,
    render_page:    Render_Page,
}

Attached_Page_Entry :: struct {
    index: int,
    key:   string,
    value: string,
}

Attached_Page_State :: struct {
    entries: ^[dynamic]Attached_Page_Entry,
    allocator: runtime.Allocator,
    collections: ^[dynamic]Debug_Collection,
    parent_path: string,
    owned_contexts: ^[dynamic]rawptr,
}

attached_page_emit :: proc "c" (
    ctx: rawptr,
    index: int,
    key: Rendered_Value,
    value: Rendered_Value,
) {
    context = runtime.default_context()
    state := transmute(^Attached_Page_State)ctx
    context.allocator = state.allocator
    append(state.entries, Attached_Page_Entry{
        index = index,
        key = strings.clone(string(key.data[:key.length])),
        value = strings.clone(string(value.data[:value.length])),
    })
}

attached_collection_emit :: proc "c" (
    ctx: rawptr,
    relative_path: Rendered_Value,
    shape: Rendered_Value,
    element_type: Rendered_Value,
    key_type: Rendered_Value,
    value_type: Rendered_Value,
    collection_ctx: rawptr,
    render_page: rawptr,
    copy_context_size: int,
    copy_context_align: int,
) {
    context = runtime.default_context()
    state := transmute(^Attached_Page_State)ctx
    context.allocator = state.allocator
    relative := string(relative_path.data[:relative_path.length])
    full_path := fmt.aprintf("%s%s", state.parent_path, relative)
    for collection in state.collections^ {
        path := string(collection.path.data[:collection.path.length])
        if path == full_path {
            delete(full_path)
            return
        }
    }
    shape_text := strings.clone(string(shape.data[:shape.length]))
    element_type_text :=
        strings.clone(string(element_type.data[:element_type.length]))
    key_type_text :=
        strings.clone(string(key_type.data[:key_type.length]))
    value_type_text :=
        strings.clone(string(value_type.data[:value_type.length]))
    retained_context := collection_ctx
    if copy_context_size > 0 {
        copied, alloc_err :=
            mem.alloc(copy_context_size, copy_context_align)
        if alloc_err != nil {
            delete(full_path)
            delete(shape_text)
            delete(element_type_text)
            delete(key_type_text)
            delete(value_type_text)
            return
        }
        mem.copy(copied, collection_ctx, copy_context_size)
        append(state.owned_contexts, copied)
        retained_context = copied
    }
    append(state.collections, Debug_Collection{
        path = Rendered_Value{
            data = raw_data(full_path),
            length = len(full_path),
        },
        shape = Rendered_Value{
            data = raw_data(shape_text),
            length = len(shape_text),
        },
        element_type = Rendered_Value{
            data = raw_data(element_type_text),
            length = len(element_type_text),
        },
        key_type = Rendered_Value{
            data = raw_data(key_type_text),
            length = len(key_type_text),
        },
        value_type = Rendered_Value{
            data = raw_data(value_type_text),
            length = len(value_type_text),
        },
        collection_ctx = retained_context,
        render_page = transmute(Render_Page)render_page,
    })
}

Attached_Collection_State :: struct {
    allocator: runtime.Allocator,
    collections: [dynamic]Debug_Collection,
    borrowed_count: int,
    owned_contexts: [dynamic]rawptr,
}

worker_attached_collections_delete :: proc(
    state: ^Attached_Collection_State,
) {
    if state == nil {
        return
    }
    if state.collections == nil && state.owned_contexts == nil {
        state^ = {}
        return
    }
    context.allocator = state.allocator
    for i in state.borrowed_count..<len(state.collections) {
        collection := state.collections[i]
        delete(string(collection.path.data[:collection.path.length]))
        delete(string(collection.shape.data[:collection.shape.length]))
        delete(string(
            collection.element_type.data[:collection.element_type.length],
        ))
        delete(string(collection.key_type.data[:collection.key_type.length]))
        delete(string(
            collection.value_type.data[:collection.value_type.length],
        ))
    }
    for owned_context in state.owned_contexts {
        _ = mem.free(owned_context)
    }
    delete(state.collections)
    delete(state.owned_contexts)
    state^ = {}
}

worker_attached_collections_begin :: proc(
    state: ^Attached_Collection_State,
    collections: []Debug_Collection,
    allocator: runtime.Allocator,
) {
    if state.collections != nil || state.owned_contexts != nil {
        worker_attached_collections_delete(state)
    }
    state.allocator = allocator
    state.borrowed_count = len(collections)
    state.collections = make(
        [dynamic]Debug_Collection,
        0,
        len(collections),
    )
    append(&state.collections, ..collections)
}

worker_render_attached_page :: proc(
    collections: ^Attached_Collection_State,
    descriptor,
    offset,
    limit: int,
) -> (
    entries: [dynamic]Attached_Page_Entry,
    total: int,
    discovered_at: int,
    ok: bool,
) {
    if collections == nil ||
       descriptor < 0 ||
       descriptor >= len(collections.collections) ||
       offset < 0 ||
       limit <= 0 {
        return entries, 0, 0, false
    }
    collection := collections.collections[descriptor]
    if collection.render_page == nil {
        return entries, 0, 0, false
    }
    discovered_at = len(collections.collections)
    parent_path :=
        string(collection.path.data[:collection.path.length])
    state := Attached_Page_State{
        entries = &entries,
        allocator = collections.allocator,
        collections = &collections.collections,
        parent_path = parent_path,
        owned_contexts = &collections.owned_contexts,
    }
    total = collection.render_page(
        collection.collection_ctx,
        offset,
        limit,
        rawptr(&state),
        attached_page_emit,
        attached_collection_emit,
    )
    return entries, total, discovered_at, total >= 0
}

attached_page_entries_delete :: proc(
    entries: []Attached_Page_Entry,
    allocator: runtime.Allocator,
) {
    context.allocator = allocator
    for entry in entries {
        delete(entry.key)
        delete(entry.value)
    }
    delete(entries)
}

Restart_Selection :: struct {
    name:  Rendered_Value,
    value: Rendered_Value,
}

Pause :: proc "c" (
    ctx: rawptr,
    pause_id: cstring,
    values: [^]Rendered_Value,
    value_count: int,
    collections: [^]Debug_Collection,
    collection_count: int,
    required: bool,
    restart_selection: ^Restart_Selection,
)

Abort_Requested :: proc "c" (ctx: rawptr) -> bool

Attached_Pause_Handler :: proc(
    ctx: rawptr,
    pause_id: string,
    values: [^]Rendered_Value,
    value_count: int,
    collections: [^]Debug_Collection,
    collection_count: int,
    restart_selection: ^Restart_Selection,
)

Attached_Condition_Handler :: proc(
    ctx: rawptr,
    pause_id,
    condition_type,
    message,
    data,
    value_type: string,
    restart_flags: u32,
)

Attached_Trace_Handler :: proc(
    ctx: rawptr,
    kind,
    trace_id: string,
    depth,
    elapsed_ns,
    delta_ns: int,
)

Attached_Trace_Values_Handler :: proc(
    ctx: rawptr,
    trace_id: string,
    values: [^]Rendered_Value,
    value_count: int,
)

Attached_Output_Handler :: proc(
    ctx: rawptr,
    stream,
    text: string,
)

Debug_Flags :: proc "c" (ctx: rawptr) -> u32

Trace_Point :: proc "c" (ctx: rawptr, trace_id: cstring)

Trace_Values :: proc "c" (
    ctx: rawptr,
    trace_id: cstring,
    values: [^]Rendered_Value,
    value_count: int,
)

Condition :: proc "c" (
    ctx: rawptr,
    pause_id: cstring,
    condition_type: Rendered_Value,
    message: Rendered_Value,
    data: Rendered_Value,
    value_type: Rendered_Value,
    restart_flags: u32,
)

Emit_Output :: proc "c" (ctx: rawptr, value: Rendered_Value)

Enter_Frame :: proc "c" (ctx: rawptr)

Leave_Frame :: proc "c" (ctx: rawptr)
Transfer_Result_Allocation :: proc "c" (
    ctx: rawptr,
    memory: rawptr,
)
Retain_Result_Allocation :: proc "c" (
    ctx: rawptr,
    memory: rawptr,
)
Transfer_Binding_Allocation :: proc "c" (
    ctx: rawptr,
    name: cstring,
    memory: rawptr,
)
Retain_Binding_Allocation :: proc "c" (
    ctx: rawptr,
    name: cstring,
    memory: rawptr,
)

Condition_Handler_Push :: proc "c" (
    ctx: rawptr,
    kind: Rendered_Value,
    handler: rawptr,
)
Condition_Handler_Pop :: proc "c" (ctx: rawptr)
Condition_Handler_Count :: proc "c" (ctx: rawptr) -> int
Condition_Handler_Kind_At :: proc "c" (
    ctx: rawptr,
    index: int,
) -> Rendered_Value
Condition_Handler_At :: proc "c" (ctx: rawptr, index: int) -> rawptr

Host_API :: struct {
    ctx:             rawptr,
    allocator:       runtime.Allocator,
    register_proc:   Register_Proc,
    lookup_proc:     Lookup_Proc,
    register_result: Register_Result,
    render_scalar_result: Render_Scalar_Result,
    register_scalar_invoke: Register_Scalar_Invoke,
    register_state:  Register_State,
    debug_flags:     Debug_Flags,
    trace_point:     Trace_Point,
    trace_values:    Trace_Values,
    condition:       Condition,
    emit_output:     Emit_Output,
    emit_stream_output: Emit_Output,
    enter_frame:     Enter_Frame,
    leave_frame:     Leave_Frame,
    pause:           Pause,
    abort_requested: Abort_Requested,
    transfer_result_allocation: Transfer_Result_Allocation,
    retain_result_allocation: Retain_Result_Allocation,
    transfer_binding_allocation: Transfer_Binding_Allocation,
    retain_binding_allocation: Retain_Binding_Allocation,
    condition_handler_push: Condition_Handler_Push,
    condition_handler_pop: Condition_Handler_Pop,
    condition_handler_count: Condition_Handler_Count,
    condition_handler_kind_at: Condition_Handler_Kind_At,
    condition_handler_at: Condition_Handler_At,
}

Condition_Handler_Entry :: struct {
    kind:    string,
    handler: rawptr,
}

Proc_Slot :: struct {
    name:      string,
    signature: string,
    address:   rawptr,
}

Scalar_Invoke_Slot :: struct {
    name:       string,
    signature:  string,
    result_abi: string,
    address:    Scalar_Invoke,
}

State_Slot :: struct {
    name:      string,
    signature: string,
    size:      int,
    align:     int,
    clone:     State_Clone,
    restore:   State_Restore,
}

Checkpoint_Entry :: struct {
    name:      string,
    signature: string,
    snapshot:  rawptr,
    size:      int,
}

Checkpoint :: struct {
    name:    string,
    entries: [dynamic]Checkpoint_Entry,
}

Generation_Symbols :: struct {
    api_version: ^u32 `dynlib:"kvist_repl_api_version"`,
    run:         proc "c" (^Host_API) `dynlib:"kvist_repl_run"`,
    stabilize_result: Stabilize_Result `dynlib:"kvist_repl_stabilize_result"`,
    path:        string,
    result_address: rawptr,
    __handle:    dynlib.Library,
}

Worker :: struct {
    allocator: runtime.Allocator,
    input_reader: ^bufio.Reader,
    generations: [dynamic]Generation_Symbols,
    proc_slots:  [dynamic]Proc_Slot,
    scalar_invoke_slots: [dynamic]Scalar_Invoke_Slot,
    incremental_backend: Incremental_LLVM_Backend,
    result_slots: [3]Proc_Slot,
    direct_int_results: [3]int,
    next_direct_int_result: int,
    direct_bool_results: [3]bool,
    next_direct_bool_result: int,
    direct_f64_results: [3]f64,
    next_direct_f64_result: int,
    direct_string_results: [3]string,
    next_direct_string_result: int,
    state_slots:  [dynamic]State_Slot,
    checkpoints:  [dynamic]Checkpoint,
    checkpoint_live_allocations: int,
    checkpoint_live_bytes:       int,
    checkpoint_total_allocations: int,
    checkpoint_total_allocated_bytes: int,
    checkpoint_total_frees:      int,
    checkpoint_total_freed_bytes: int,
    generation_allocator: mem.Tracking_Allocator,
    generation_allocator_initialized: bool,
    managed_allocations: map[rawptr]Worker_Managed_Allocation,
    managed_transfers: [dynamic]Worker_Managed_Transfer,
    managed_allocation_mutex: sync.Mutex,
    next_managed_allocation: int,
    next_managed_transfer: int,
    host_api:    Host_API,
    condition_handlers: [dynamic]Condition_Handler_Entry,
    step_armed:  bool,
    step_mode:   Step_Mode,
    step_depth:  int,
    frame_depth: int,
    trace_enabled: bool,
    trace_remaining: int,
    trace_limit_reported: bool,
    trace_started_at: time.Tick,
    trace_last_at: time.Tick,
    trace_values_enabled: bool,
    trace_values_remaining: int,
    trace_values_limit_reported: bool,
    restart_name:     string,
    restart_value:    string,
    restart_payloads: [dynamic]string,
    abort_requested:  bool,
    abort_unwind_depth: int,
    last_run_aborted: bool,
    incremental_call_failed: bool,
    output:           string,
    emit_output_to_stdout: bool,
    attached_pause_ctx: rawptr,
    attached_pause_handler: Attached_Pause_Handler,
    attached_condition_ctx: rawptr,
    attached_condition_handler: Attached_Condition_Handler,
    attached_trace_ctx: rawptr,
    attached_trace_handler: Attached_Trace_Handler,
    attached_trace_values_ctx: rawptr,
    attached_trace_values_handler: Attached_Trace_Values_Handler,
    attached_output_ctx: rawptr,
    attached_output_handler: Attached_Output_Handler,
}

worker_direct_result_owner: ^Worker

worker_direct_int_result_0 :: proc() -> int {
    return worker_direct_result_owner.direct_int_results[0]
}

worker_direct_int_result_1 :: proc() -> int {
    return worker_direct_result_owner.direct_int_results[1]
}

worker_direct_int_result_2 :: proc() -> int {
    return worker_direct_result_owner.direct_int_results[2]
}

worker_direct_bool_result_0 :: proc() -> bool { return worker_direct_result_owner.direct_bool_results[0] }
worker_direct_bool_result_1 :: proc() -> bool { return worker_direct_result_owner.direct_bool_results[1] }
worker_direct_bool_result_2 :: proc() -> bool { return worker_direct_result_owner.direct_bool_results[2] }
worker_direct_f64_result_0 :: proc() -> f64 { return worker_direct_result_owner.direct_f64_results[0] }
worker_direct_f64_result_1 :: proc() -> f64 { return worker_direct_result_owner.direct_f64_results[1] }
worker_direct_f64_result_2 :: proc() -> f64 { return worker_direct_result_owner.direct_f64_results[2] }
worker_direct_string_result_0 :: proc() -> string { return worker_direct_result_owner.direct_string_results[0] }
worker_direct_string_result_1 :: proc() -> string { return worker_direct_result_owner.direct_string_results[1] }
worker_direct_string_result_2 :: proc() -> string { return worker_direct_result_owner.direct_string_results[2] }
Worker_Allocation_Stats :: struct {
    live_allocations:        int,
    live_bytes:              int,
    total_allocations:       int,
    total_allocated_bytes:   int,
    total_frees:             int,
    total_freed_bytes:       int,
    managed_live_allocations: int,
    managed_live_bytes:       int,
    managed_peak_bytes:       int,
    managed_total_allocations: int,
    managed_total_allocated_bytes: int,
    managed_total_frees:      int,
    managed_total_freed_bytes: int,
}

Worker_Managed_Allocation :: struct {
    allocation: int,
    size:       int,
    alignment:  int,
    generation: int,
    owner_kind: Worker_Managed_Owner_Kind,
    owner_generation: int,
    owner_name: string,
    retained_result_generations: [dynamic]int,
    retained_binding_owners: [dynamic]Worker_Managed_Binding_Owner,
}

Worker_Managed_Owner_Kind :: enum {
    Generation,
    Result,
    Binding,
}

Worker_Managed_Binding_Owner :: struct {
    name: string,
    generation: int,
}

Worker_Managed_Transfer :: struct {
    sequence:        int,
    allocation:      int,
    generation:      int,
    owner_from_kind: Worker_Managed_Owner_Kind,
    owner_from_generation: int,
    owner_from_name: string,
    owner_to_kind:   Worker_Managed_Owner_Kind,
    owner_to_generation: int,
    owner_to_name: string,
    action: Worker_Managed_Transfer_Action,
}

worker_managed_allocation_metadata_delete :: proc(
    allocation: ^Worker_Managed_Allocation,
    allocator: runtime.Allocator,
) {
    delete(allocation.owner_name, allocator)
    delete(allocation.retained_result_generations)
    for owner in allocation.retained_binding_owners {
        delete(owner.name, allocator)
    }
    delete(allocation.retained_binding_owners)
    allocation^ = {}
}

Worker_Managed_Transfer_Action :: enum {
    Transferred,
    Retained,
}

worker_managed_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: runtime.Allocator_Mode,
    size,
    alignment: int,
    old_memory: rawptr,
    old_size: int,
    location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
    worker := (^Worker)(allocator_data)
    tracked := mem.tracking_allocator(
        &worker.generation_allocator,
    )
    result, alloc_err := tracked.procedure(
        tracked.data,
        mode,
        size,
        alignment,
        old_memory,
        old_size,
        location,
    )
    if alloc_err != nil {
        return result, alloc_err
    }
    result_memory := rawptr(raw_data(result))
    sync.mutex_guard(&worker.managed_allocation_mutex)
    #partial switch mode {
    case .Alloc, .Alloc_Non_Zeroed:
        if result_memory != nil {
            worker.next_managed_allocation += 1
            worker.managed_allocations[result_memory] =
                Worker_Managed_Allocation{
                    allocation = worker.next_managed_allocation,
                    size = size,
                    alignment = alignment,
                    generation = len(worker.generations),
                    owner_kind = .Generation,
                    owner_generation = len(worker.generations),
                }
        }
    case .Free:
        if old_memory != nil {
            if allocation, found :=
                worker.managed_allocations[old_memory];
               found {
                worker_managed_allocation_metadata_delete(
                    &allocation,
                    worker.allocator,
                )
            }
            delete_key(&worker.managed_allocations, old_memory)
        }
    case .Resize, .Resize_Non_Zeroed:
        if old_memory != nil {
            if allocation, found :=
                worker.managed_allocations[old_memory];
               found {
                worker_managed_allocation_metadata_delete(
                    &allocation,
                    worker.allocator,
                )
            }
            delete_key(&worker.managed_allocations, old_memory)
        }
        if result_memory != nil {
            worker.next_managed_allocation += 1
            worker.managed_allocations[result_memory] =
                Worker_Managed_Allocation{
                    allocation = worker.next_managed_allocation,
                    size = size,
                    alignment = alignment,
                    generation = len(worker.generations),
                    owner_kind = .Generation,
                    owner_generation = len(worker.generations),
                }
        }
    }
    return result, alloc_err
}

Step_Mode :: enum {
    Into,
    Over,
    Out,
}

RESULT_SLOT_NAMES := [3]string{
    "kvist_repl_star_1",
    "kvist_repl_star_2",
    "kvist_repl_star_3",
}

worker_register_proc :: proc "c" (
    context_ptr: rawptr,
    name_ptr: cstring,
    signature_ptr: cstring,
    address: rawptr,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    context.allocator = worker.allocator
    name := string(name_ptr)
    signature := string(signature_ptr)
    for &slot in worker.proc_slots {
        if slot.name == name && slot.signature == signature {
            slot.address = address
            return
        }
    }
    append(&worker.proc_slots, Proc_Slot{
        name = strings.clone(name),
        signature = strings.clone(signature),
        address = address,
    })
}

worker_register_scalar_invoke :: proc "c" (
    context_ptr: rawptr,
    name_ptr: cstring,
    signature_ptr: cstring,
    result_abi_ptr: cstring,
    address: Scalar_Invoke,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    context.allocator = worker.allocator
    name := string(name_ptr)
    signature := string(signature_ptr)
    result_abi := string(result_abi_ptr)
    for &slot in worker.scalar_invoke_slots {
        if slot.name == name && slot.signature == signature {
            delete(slot.result_abi)
            slot.result_abi = strings.clone(result_abi)
            slot.address = address
            return
        }
    }
    append(&worker.scalar_invoke_slots, Scalar_Invoke_Slot{
        name = strings.clone(name),
        signature = strings.clone(signature),
        result_abi = strings.clone(result_abi),
        address = address,
    })
}

worker_register_state :: proc "c" (
    context_ptr: rawptr,
    name_ptr: cstring,
    signature_ptr: cstring,
    size,
    align: int,
    clone: State_Clone,
    restore: State_Restore,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    context.allocator = worker.allocator
    name := string(name_ptr)
    signature := string(signature_ptr)
    // A source name denotes one current mutable cell. Re-registering the same
    // name after a compatible definition refreshes its codec; a changed
    // signature remains visible so restore can reject the stale checkpoint.
    for &slot in worker.state_slots {
        if slot.name == name {
            if slot.signature != signature {
                delete(slot.signature)
                slot.signature = strings.clone(signature)
            }
            slot.clone = clone
            slot.restore = restore
            slot.size = size
            slot.align = align
            return
        }
    }
    append(&worker.state_slots, State_Slot{
        name = strings.clone(name),
        signature = strings.clone(signature),
        size = size,
        align = align,
        clone = clone,
        restore = restore,
    })
}

worker_lookup_proc :: proc "c" (
    context_ptr: rawptr,
    name_ptr: cstring,
    signature_ptr: cstring,
) -> rawptr {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    context.allocator = worker.allocator
    name := string(name_ptr)
    signature := string(signature_ptr)
    for slot in worker.result_slots {
        if slot.name == name && slot.signature == signature {
            return slot.address
        }
    }
    for slot in worker.proc_slots {
        if slot.name == name && slot.signature == signature {
            return slot.address
        }
    }
    return nil
}

worker_register_result :: proc "c" (
    context_ptr: rawptr,
    signature_ptr: cstring,
    address: rawptr,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    context.allocator = worker.allocator

    next_slots: [3]Proc_Slot
    if worker.result_slots[1].name != "" {
        next_slots[2] = {
            name = strings.clone(RESULT_SLOT_NAMES[2]),
            signature = strings.clone(worker.result_slots[1].signature),
            address = worker.result_slots[1].address,
        }
    }
    if worker.result_slots[0].name != "" {
        next_slots[1] = {
            name = strings.clone(RESULT_SLOT_NAMES[1]),
            signature = strings.clone(worker.result_slots[0].signature),
            address = worker.result_slots[0].address,
        }
    }
    for slot in worker.result_slots {
        delete(slot.name)
        delete(slot.signature)
    }
    worker.result_slots[0] = Proc_Slot{
        name = strings.clone(RESULT_SLOT_NAMES[0]),
        signature = strings.clone(string(signature_ptr)),
        address = address,
    }
    worker.result_slots[1] = next_slots[1]
    worker.result_slots[2] = next_slots[2]
}

worker_stabilize_loaded_result :: proc(
    worker: ^Worker,
    generation: ^Generation_Symbols,
) -> bool {
    if worker == nil || generation == nil ||
       generation.result_address == nil {
        return true
    }
    referenced := false
    for slot in worker.result_slots {
        if slot.address == generation.result_address {
            referenced = true
            break
        }
    }
    if !referenced {
        return true
    }
    if generation.stabilize_result == nil {
        return false
    }
    occupied: [3]rawptr
    for slot, index in worker.result_slots {
        occupied[index] = slot.address
    }
    stable_address := generation.stabilize_result(
        raw_data(occupied[:]),
        len(occupied),
    )
    if stable_address == nil {
        return false
    }
    for &slot in worker.result_slots {
        if slot.address == generation.result_address {
            slot.address = stable_address
        }
    }
    return true
}

worker_render_scalar_result :: proc "c" (
    context_ptr: rawptr,
    type_name_ptr: cstring,
    address: rawptr,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    context.allocator = worker.allocator
    if address == nil || type_name_ptr == nil {
        return
    }
    type_name := string(type_name_ptr)
    rendered := ""
    switch type_name {
    case "bool":    rendered = fmt.aprintf("%v\n", (transmute(proc() -> bool)address)())
    case "int":     rendered = fmt.aprintf("%v\n", (transmute(proc() -> int)address)())
    case "i8":      rendered = fmt.aprintf("%v\n", (transmute(proc() -> i8)address)())
    case "i16":     rendered = fmt.aprintf("%v\n", (transmute(proc() -> i16)address)())
    case "i32":     rendered = fmt.aprintf("%v\n", (transmute(proc() -> i32)address)())
    case "i64":     rendered = fmt.aprintf("%v\n", (transmute(proc() -> i64)address)())
    case "i128":    rendered = fmt.aprintf("%v\n", (transmute(proc() -> i128)address)())
    case "uint":    rendered = fmt.aprintf("%v\n", (transmute(proc() -> uint)address)())
    case "u8":      rendered = fmt.aprintf("%v\n", (transmute(proc() -> u8)address)())
    case "u16":     rendered = fmt.aprintf("%v\n", (transmute(proc() -> u16)address)())
    case "u32":     rendered = fmt.aprintf("%v\n", (transmute(proc() -> u32)address)())
    case "u64":     rendered = fmt.aprintf("%v\n", (transmute(proc() -> u64)address)())
    case "u128":    rendered = fmt.aprintf("%v\n", (transmute(proc() -> u128)address)())
    case "uintptr": rendered = fmt.aprintf("%v\n", (transmute(proc() -> uintptr)address)())
    case "f32":     rendered = fmt.aprintf("%v\n", (transmute(proc() -> f32)address)())
    case "f64":     rendered = fmt.aprintf("%v\n", (transmute(proc() -> f64)address)())
    case "string":  rendered = fmt.aprintf("%v\n", (transmute(proc() -> string)address)())
    case:
        return
    }
    defer delete(rendered)
    worker_emit_output(
        context_ptr,
        Rendered_Value{data = raw_data(rendered), length = len(rendered)},
    )
}

worker_invoke_int :: proc(
    worker: ^Worker,
    name,
    signature: string,
    args: []int,
) -> bool {
    if worker == nil || len(args) > 4 {
        return false
    }
    address: rawptr
    for slot in worker.proc_slots {
        if slot.name == name && slot.signature == signature {
            address = slot.address
            break
        }
    }
    if address == nil {
        return false
    }
    context = runtime.default_context()
    context.allocator = worker.allocator
    worker.abort_requested = false
    worker.last_run_aborted = false
    worker.incremental_call_failed = false
    value: int
    switch len(args) {
    case 0: value = (transmute(proc() -> int)address)()
    case 1: value = (transmute(proc(int) -> int)address)(args[0])
    case 2: value = (transmute(proc(int, int) -> int)address)(args[0], args[1])
    case 3: value = (transmute(proc(int, int, int) -> int)address)(args[0], args[1], args[2])
    case 4: value = (transmute(proc(int, int, int, int) -> int)address)(args[0], args[1], args[2], args[3])
    }
    worker.last_run_aborted = worker.abort_requested
    worker.abort_requested = false
    if worker.last_run_aborted {
        return true
    }
    cell := worker.next_direct_int_result % len(worker.direct_int_results)
    worker.next_direct_int_result += 1
    worker.direct_int_results[cell] = value
    worker_direct_result_owner = worker
    result_address := transmute(rawptr)worker_direct_int_result_0
    if cell == 1 {
        result_address = transmute(rawptr)worker_direct_int_result_1
    } else if cell == 2 {
        result_address = transmute(rawptr)worker_direct_int_result_2
    }
    worker_register_result(
        rawptr(worker),
        cstring("value:int"),
        result_address,
    )
    rendered := fmt.aprintf("%v\n", value)
    defer delete(rendered)
    worker_emit_output(
        rawptr(worker),
        Rendered_Value{data = raw_data(rendered), length = len(rendered)},
    )
    return true
}

worker_store_scalar_result :: proc(
    worker: ^Worker,
    result: Scalar_Value,
    data_result_abi := "",
) -> bool {
    if worker == nil {
        return false
    }
    context = runtime.default_context()
    context.allocator = worker.allocator
    worker_direct_result_owner = worker
    signature_text := ""
    result_address: rawptr
    rendered := ""
    defer delete(rendered)
    switch result.kind {
    case .Bool:
        cell := worker.next_direct_bool_result % len(worker.direct_bool_results)
        worker.next_direct_bool_result += 1
        worker.direct_bool_results[cell] = result.int_value != 0
        addresses := [?]rawptr{
            transmute(rawptr)worker_direct_bool_result_0,
            transmute(rawptr)worker_direct_bool_result_1,
            transmute(rawptr)worker_direct_bool_result_2,
        }
        result_address = addresses[cell]
        signature_text = "value:bool"
        rendered = fmt.aprintf("%v\n", worker.direct_bool_results[cell])
    case .Int:
        cell := worker.next_direct_int_result % len(worker.direct_int_results)
        worker.next_direct_int_result += 1
        worker.direct_int_results[cell] = int(result.int_value)
        addresses := [?]rawptr{
            transmute(rawptr)worker_direct_int_result_0,
            transmute(rawptr)worker_direct_int_result_1,
            transmute(rawptr)worker_direct_int_result_2,
        }
        result_address = addresses[cell]
        signature_text = "value:int"
        rendered = fmt.aprintf("%v\n", worker.direct_int_results[cell])
    case .F64:
        cell := worker.next_direct_f64_result % len(worker.direct_f64_results)
        worker.next_direct_f64_result += 1
        worker.direct_f64_results[cell] = result.float_value
        addresses := [?]rawptr{
            transmute(rawptr)worker_direct_f64_result_0,
            transmute(rawptr)worker_direct_f64_result_1,
            transmute(rawptr)worker_direct_f64_result_2,
        }
        result_address = addresses[cell]
        signature_text = "value:f64"
        rendered = fmt.aprintf("%v\n", worker.direct_f64_results[cell])
    case .String:
        cell := worker.next_direct_string_result % len(worker.direct_string_results)
        worker.next_direct_string_result += 1
        value := string(result.string_data[:result.string_length])
        copied_value := strings.clone(value)
        if result.owned {
            worker_release_owned_scalar_value(worker, result)
        }
        // The source can be a borrowed *3 result that is about to reuse this
        // ring cell. Copy it before releasing the destination cell.
        delete(worker.direct_string_results[cell])
        worker.direct_string_results[cell] = copied_value
        addresses := [?]rawptr{
            transmute(rawptr)worker_direct_string_result_0,
            transmute(rawptr)worker_direct_string_result_1,
            transmute(rawptr)worker_direct_string_result_2,
        }
        result_address = addresses[cell]
        signature_text = "value:string"
        rendered = fmt.aprintf("%s\n", worker.direct_string_results[cell])
    case .Data:
        if data_result_abi == "" || result.managed_render == nil {
            worker_release_owned_scalar_value(worker, result)
            return false
        }
        rendered_value := Rendered_Value{}
        if !result.managed_render(result.managed_context, &rendered_value) {
            worker_release_owned_scalar_value(worker, result)
            return false
        }
        if rendered_value.length < 0 ||
           (rendered_value.length > 0 && rendered_value.data == nil) {
            worker_release_owned_scalar_value(worker, result)
            return false
        }
        value := string(rendered_value.data[:rendered_value.length])
        rendered = fmt.aprintf("%s\n", value)
        result_address = result.result_address
        if result.managed_commit != nil {
            result_address = result.managed_commit(
                result.managed_context,
            )
        }
        if result_address == nil {
            worker_release_owned_scalar_value(worker, result)
            return false
        }
        signature_text = data_result_abi
        if result.owned {
            worker_release_owned_scalar_value(worker, result)
        }
    case .Invalid:
        return false
    }
    worker_register_result(
        rawptr(worker),
        cstring(raw_data(signature_text)),
        result_address,
    )
    worker_emit_output(
        rawptr(worker),
        Rendered_Value{data = raw_data(rendered), length = len(rendered)},
    )
    return true
}

worker_execution_plan_result :: proc(
    worker: ^Worker,
    index: int,
) -> (Scalar_Value, bool) {
    if worker == nil || index < 0 || index >= len(worker.result_slots) {
        return {}, false
    }
    slot := &worker.result_slots[index]
    if slot.address == nil {
        return {}, false
    }
    switch slot.signature {
    case "value:bool":
        value := (transmute(proc() -> bool)slot.address)()
        return Scalar_Value{
            kind = .Bool,
            int_value = 1 if value else 0,
        }, true
    case "value:int":
        value := (transmute(proc() -> int)slot.address)()
        return Scalar_Value{
            kind = .Int,
            int_value = i64(value),
        }, true
    case "value:f64":
        value := (transmute(proc() -> f64)slot.address)()
        return Scalar_Value{
            kind = .F64,
            float_value = value,
        }, true
    case "value:string":
        value := (transmute(proc() -> string)slot.address)()
        return Scalar_Value{
            kind = .String,
            string_data = raw_data(value),
            string_length = len(value),
        }, true
    }
    if strings.has_prefix(slot.signature, "value:Data") {
        return Scalar_Value{
            kind = .Data,
            source_address = slot.address,
            result_address = slot.address,
        }, true
    }
    return {}, false
}

worker_scalar_invoke_target :: proc(
    target: string,
) -> (name, signature: string, ok: bool) {
    separator := -1
    for index := 0; index < len(target); index += 1 {
        if target[index] == 0 {
            if separator >= 0 {
                return "", "", false
            }
            separator = index
        }
    }
    if separator <= 0 || separator+1 >= len(target) {
        return "", "", false
    }
    return target[:separator], target[separator+1:], true
}

worker_find_scalar_invoke :: proc(
    worker: ^Worker,
    name,
    signature: string,
) -> ^Scalar_Invoke_Slot {
    if worker == nil {
        return nil
    }
    for &slot in worker.scalar_invoke_slots {
        if slot.name == name && slot.signature == signature {
            return &slot
        }
    }
    return nil
}

worker_call_scalar_invoke :: proc(
    worker: ^Worker,
    invoke_slot: ^Scalar_Invoke_Slot,
    args: []Scalar_Value,
) -> (result: Scalar_Value, aborted, ok: bool) {
    if worker == nil || invoke_slot == nil || invoke_slot.address == nil ||
       len(args) > 4 {
        return {}, false, false
    }
    context = runtime.default_context()
    context.allocator = worker.allocator
    worker.abort_requested = false
    worker.last_run_aborted = false
    worker.incremental_call_failed = false
    invoked := invoke_slot.address(raw_data(args), len(args), &result)
    worker.last_run_aborted = worker.abort_requested
    worker.abort_requested = false
    if !invoked {
        return {}, false, false
    }
    return result, worker.last_run_aborted, true
}

WORKER_PLAN_MAX_OWNED_STRING_BYTES :: 64 * 1024 * 1024
WORKER_PLAN_MAX_OWNED_VALUES :: repl_plan.MAX_INSTRUCTIONS

Worker_Plan_Owned_Value :: struct {
    scalar:     Scalar_Value,
    references: int,
    active:     bool,
}

Worker_Plan_Owned_Values :: struct {
    values:            [dynamic]Worker_Plan_Owned_Value,
    live_values:       int,
    live_string_bytes: int,
}

Worker_Plan_Value :: struct {
    scalar: Scalar_Value,
    // One-based index into the execution's owned-value table. Zero means that
    // the scalar does not depend on an execution-owned allocation.
    owner:  int,
}

worker_owned_scalar_allocator :: proc(worker: ^Worker) -> runtime.Allocator {
    if worker != nil && worker.generation_allocator_initialized &&
       worker.host_api.allocator.procedure != nil {
        return worker.host_api.allocator
    }
    if worker != nil {
        return worker.allocator
    }
    return context.allocator
}

worker_release_owned_scalar_value :: proc(
    worker: ^Worker,
    value: Scalar_Value,
) {
    if !value.owned {
        return
    }
    if value.managed_release != nil {
        if value.managed_context != nil {
            value.managed_release(value.managed_context)
        }
        return
    }
    if (value.kind != .String && value.kind != .Data) ||
       value.string_length < 0 ||
       (value.string_length > 0 && value.string_data == nil) {
        return
    }
    owned := string(value.string_data[:value.string_length])
    delete(owned, worker_owned_scalar_allocator(worker))
}

worker_plan_owned_value_contains_string :: proc(
    owned: Worker_Plan_Owned_Value,
    value: Scalar_Value,
) -> bool {
    if !owned.active || owned.scalar.kind != .String ||
       owned.scalar.string_length <= 0 ||
       owned.scalar.string_data == nil ||
       value.kind != .String || value.string_length < 0 ||
       value.string_length > owned.scalar.string_length ||
       value.string_data == nil {
        return false
    }
    owned_start := uintptr(rawptr(owned.scalar.string_data))
    value_start := uintptr(rawptr(value.string_data))
    if value_start < owned_start {
        return false
    }
    return value_start-owned_start <=
           uintptr(owned.scalar.string_length-value.string_length)
}

worker_plan_owned_value_release :: proc(
    worker: ^Worker,
    owned_values: ^Worker_Plan_Owned_Values,
    owner: int,
) {
    index := owner-1
    if owned_values == nil || index < 0 ||
       index >= len(owned_values.values) {
        return
    }
    owned := &owned_values.values[index]
    if !owned.active || owned.references <= 0 {
        return
    }
    owned.references -= 1
    if owned.references > 0 {
        return
    }
    worker_release_owned_scalar_value(worker, owned.scalar)
    if owned.scalar.kind == .String {
        owned_values.live_string_bytes -= owned.scalar.string_length
    }
    owned_values.live_values -= 1
    owned^ = {}
}

worker_plan_owned_value_retain_string_alias :: proc(
    owned_values: ^Worker_Plan_Owned_Values,
    value: Scalar_Value,
) -> int {
    if owned_values == nil {
        return 0
    }
    for &owned, index in owned_values.values {
        if worker_plan_owned_value_contains_string(owned, value) {
            owned.references += 1
            return index+1
        }
    }
    return 0
}

worker_plan_owned_value_adopt :: proc(
    worker: ^Worker,
    owned_values: ^Worker_Plan_Owned_Values,
    result: Scalar_Value,
) -> (Worker_Plan_Value, bool) {
    value := result
    value.owned = false
    if owned_values == nil || !result.owned ||
       (result.kind != .String && result.kind != .Data) {
        return {}, false
    }
    if result.kind == .String &&
       (result.string_length < 0 ||
        (result.string_length > 0 && result.string_data == nil)) {
        return {}, false
    }
    if result.kind == .Data &&
       (result.source_value == nil || result.managed_context == nil ||
        result.managed_release == nil || result.managed_commit == nil ||
        result.managed_render == nil) {
        return {}, false
    }
    if result.kind == .String && result.string_length == 0 {
        worker_release_owned_scalar_value(worker, result)
        value.string_data = nil
        return Worker_Plan_Value{scalar = value}, true
    }
    if owned_values.live_values >= WORKER_PLAN_MAX_OWNED_VALUES ||
       (result.kind == .String &&
        (result.string_length > WORKER_PLAN_MAX_OWNED_STRING_BYTES ||
         owned_values.live_string_bytes >
         WORKER_PLAN_MAX_OWNED_STRING_BYTES-result.string_length)) {
        return {}, false
    }
    slot := -1
    for owned, index in owned_values.values {
        if !owned.active {
            slot = index
            break
        }
    }
    entry := Worker_Plan_Owned_Value{
        scalar = result,
        references = 1,
        active = true,
    }
    if slot < 0 {
        append(&owned_values.values, entry)
        slot = len(owned_values.values)-1
    } else {
        owned_values.values[slot] = entry
    }
    owned_values.live_values += 1
    if result.kind == .String {
        owned_values.live_string_bytes += result.string_length
    }
    return Worker_Plan_Value{scalar = value, owner = slot+1}, true
}

worker_plan_value_release :: proc(
    worker: ^Worker,
    owned_values: ^Worker_Plan_Owned_Values,
    value: Worker_Plan_Value,
) {
    worker_plan_owned_value_release(worker, owned_values, value.owner)
}

worker_plan_value_retain :: proc(
    owned_values: ^Worker_Plan_Owned_Values,
    value: Worker_Plan_Value,
) -> Worker_Plan_Value {
    if value.owner > 0 && value.owner <= len(owned_values.values) {
        owned := &owned_values.values[value.owner-1]
        if owned.active {
            owned.references += 1
        }
    }
    return value
}

worker_plan_owned_values_delete :: proc(
    worker: ^Worker,
    owned_values: ^Worker_Plan_Owned_Values,
) {
    if owned_values == nil {
        return
    }
    for &owned in owned_values.values {
        if !owned.active {
            continue
        }
        worker_release_owned_scalar_value(worker, owned.scalar)
        owned = {}
    }
    delete(owned_values.values)
    owned_values^ = {}
}

worker_plan_scalar_result_valid :: proc(
    result: Scalar_Value,
    invoke_slot: ^Scalar_Invoke_Slot,
) -> bool {
    if invoke_slot == nil {
        return false
    }
    switch invoke_slot.result_abi {
    case "value:bool": return result.kind == .Bool
    case "value:int":  return result.kind == .Int
    case "value:f64":  return result.kind == .F64
    case "value:string":
        expected_owned := strings.has_suffix(
            invoke_slot.signature,
            ")->string:owned",
        )
        expected_borrowed := strings.has_suffix(
            invoke_slot.signature,
            ")->string:borrowed",
        )
        return result.kind == .String &&
               (expected_owned || expected_borrowed) &&
               result.owned == expected_owned &&
               result.string_length >= 0 &&
               (result.string_length == 0 || result.string_data != nil)
    case "value:Data":
        return result.kind == .Data && result.owned &&
               result.source_value != nil &&
               result.managed_context != nil &&
               result.managed_release != nil &&
               result.managed_commit != nil &&
               result.managed_render != nil
    }
    return false
}

worker_plan_scalar_result_supported :: proc(
    invoke_slot: ^Scalar_Invoke_Slot,
) -> bool {
    if invoke_slot == nil {
        return false
    }
    switch invoke_slot.result_abi {
    case "value:bool", "value:int", "value:f64":
        return true
    case "value:string":
        return strings.has_suffix(
            invoke_slot.signature,
            ")->string:borrowed",
        ) || strings.has_suffix(
            invoke_slot.signature,
            ")->string:owned",
        )
    case "value:Data":
        return strings.has_suffix(
            invoke_slot.signature,
            ")->Data:borrowed",
        ) || strings.has_suffix(
            invoke_slot.signature,
            ")->Data:owned",
        )
    }
    return false
}

worker_execute_plan :: proc(
    worker: ^Worker,
    encoded: string,
) -> (message: string, ok: bool) {
    if worker == nil {
        return strings.clone("REPL worker is unavailable"), false
    }
    if worker.allocator.procedure == nil {
        worker.allocator = context.allocator
    }
    context = runtime.default_context()
    context.allocator = worker.allocator
    worker.last_run_aborted = false
    delete(worker.output)
    worker.output = ""
    plan, decoded := repl_plan.execution_plan_decode(encoded)
    if !decoded {
        return strings.clone("invalid resident execution plan"), false
    }
    defer repl_plan.execution_plan_delete(&plan)
    owned_values := Worker_Plan_Owned_Values{}
    defer worker_plan_owned_values_delete(worker, &owned_values)
    stack: [dynamic]Worker_Plan_Value
    defer delete(stack)
    locals: [dynamic]Worker_Plan_Value
    defer delete(locals)
    initialized_locals: [dynamic]bool
    defer delete(initialized_locals)
    pc := 0
    for pc < len(plan.instructions) {
        if len(stack) > repl_plan.MAX_INSTRUCTIONS {
            return strings.clone(
                "resident execution plan stack limit exceeded",
            ), false
        }
        instruction := plan.instructions[pc]
        switch instruction.opcode {
        case .Push_Bool:
            append(&stack, Worker_Plan_Value{
                scalar = {
                    kind = .Bool,
                    int_value = i64(instruction.operand),
                },
            })
        case .Push_Int:
            append(&stack, Worker_Plan_Value{
                scalar = {
                    kind = .Int,
                    int_value = i64(instruction.operand),
                },
            })
        case .Push_F64:
            bits := i64(instruction.operand)
            append(&stack, Worker_Plan_Value{
                scalar = {
                    kind = .F64,
                    float_value = transmute(f64)bits,
                },
            })
        case .Push_String:
            append(&stack, Worker_Plan_Value{
                scalar = {
                    kind = .String,
                    string_data = raw_data(instruction.text_operand),
                    string_length = len(instruction.text_operand),
                },
            })
        case .Invoke_Scalar_0, .Invoke_Scalar_1, .Invoke_Scalar_2,
             .Invoke_Scalar_3, .Invoke_Scalar_4:
            arity, arity_ok :=
                repl_plan.opcode_scalar_invoke_arity(instruction.opcode)
            name, signature, target_ok :=
                worker_scalar_invoke_target(instruction.text_operand)
            if !arity_ok || !target_ok || len(stack) < arity {
                return strings.clone(
                    "invalid resident scalar invocation",
                ), false
            }
            invoke_slot := worker_find_scalar_invoke(worker, name, signature)
            if !worker_plan_scalar_result_supported(invoke_slot) {
                return strings.clone(
                    "resident scalar adapter is unavailable",
                ), false
            }
            arguments_start := len(stack)-arity
            scalar_arguments: [4]Scalar_Value
            for argument, index in stack[arguments_start:] {
                scalar_arguments[index] = argument.scalar
            }
            result, aborted, invoked := worker_call_scalar_invoke(
                worker,
                invoke_slot,
                scalar_arguments[:arity],
            )
            if !invoked {
                return strings.clone(
                    "resident scalar adapter invocation failed",
                ), false
            }
            if aborted {
                worker_release_owned_scalar_value(worker, result)
                for argument in stack[arguments_start:] {
                    worker_plan_value_release(
                        worker,
                        &owned_values,
                        argument,
                    )
                }
                resize(&stack, arguments_start)
                return "", true
            }
            if !worker_plan_scalar_result_valid(
                result,
                invoke_slot,
            ) {
                worker_release_owned_scalar_value(worker, result)
                for argument in stack[arguments_start:] {
                    worker_plan_value_release(
                        worker,
                        &owned_values,
                        argument,
                    )
                }
                resize(&stack, arguments_start)
                return strings.clone(
                    "resident scalar adapter invocation failed",
                ), false
            }
            plan_result := Worker_Plan_Value{scalar = result}
            if result.owned {
                adopted := false
                plan_result, adopted = worker_plan_owned_value_adopt(
                    worker,
                    &owned_values,
                    result,
                )
                if !adopted {
                    worker_release_owned_scalar_value(worker, result)
                    for argument in stack[arguments_start:] {
                        worker_plan_value_release(
                            worker,
                            &owned_values,
                            argument,
                        )
                    }
                    resize(&stack, arguments_start)
                    return strings.clone(
                        "resident execution plan managed value limit exceeded",
                    ), false
                }
            } else if result.kind == .String {
                plan_result.owner =
                    worker_plan_owned_value_retain_string_alias(
                        &owned_values,
                        result,
                    )
            }
            for argument in stack[arguments_start:] {
                worker_plan_value_release(
                    worker,
                    &owned_values,
                    argument,
                )
            }
            resize(&stack, arguments_start)
            append(&stack, plan_result)
        case .Load_Result:
            value, loaded :=
                worker_execution_plan_result(worker, instruction.operand)
            if !loaded {
                return strings.clone(
                    "resident execution plan result is unavailable",
                ), false
            }
            append(&stack, Worker_Plan_Value{scalar = value})
        case .Store_Local:
            if len(stack) < 1 || instruction.operand < 0 ||
               instruction.operand >= repl_plan.MAX_INSTRUCTIONS {
                return strings.clone(
                    "invalid resident local store",
                ), false
            }
            if instruction.operand >= len(locals) {
                resize(&locals, instruction.operand+1)
                resize(&initialized_locals, instruction.operand+1)
            }
            if initialized_locals[instruction.operand] {
                worker_plan_value_release(
                    worker,
                    &owned_values,
                    locals[instruction.operand],
                )
            }
            locals[instruction.operand] = stack[len(stack)-1]
            initialized_locals[instruction.operand] = true
            resize(&stack, len(stack)-1)
        case .Load_Local:
            if instruction.operand < 0 ||
               instruction.operand >= len(locals) ||
               !initialized_locals[instruction.operand] {
                return strings.clone(
                    "resident execution plan local is unavailable",
                ), false
            }
            append(
                &stack,
                worker_plan_value_retain(
                    &owned_values,
                    locals[instruction.operand],
                ),
            )
        case .Add, .Subtract, .Multiply, .Divide, .Modulo:
            arity := instruction.operand
            if arity <= 0 || len(stack) < arity {
                return strings.clone(
                    "invalid resident execution plan stack",
                ), false
            }
            start := len(stack)-arity
            operand_kind := stack[start].scalar.kind
            if operand_kind != .Int && operand_kind != .F64 {
                return strings.clone(
                    "resident arithmetic expects numeric operands",
                ), false
            }
            for value in stack[start:] {
                if value.scalar.kind != operand_kind {
                    return strings.clone(
                        "resident arithmetic expects matching operand types",
                    ), false
                }
            }
            result := Scalar_Value{kind = operand_kind}
            if operand_kind == .Int {
                result_int := int(stack[start].scalar.int_value)
                if instruction.opcode == .Subtract && arity == 1 {
                    result_int = -result_int
                }
                for value in stack[start+1:] {
                    operand := int(value.scalar.int_value)
                    #partial switch instruction.opcode {
                    case .Add:      result_int += operand
                    case .Subtract: result_int -= operand
                    case .Multiply: result_int *= operand
                    case .Divide:
                        if operand == 0 ||
                           (result_int == min(int) && operand == -1) {
                            return strings.clone(
                                "invalid resident integer division",
                            ), false
                        }
                        result_int /= operand
                    case .Modulo:
                        if operand == 0 {
                            return strings.clone(
                                "invalid resident integer modulo",
                            ), false
                        }
                        if result_int == min(int) && operand == -1 {
                            result_int = 0
                        } else {
                            result_int %= operand
                        }
                    case:
                    }
                }
                result.int_value = i64(result_int)
            } else {
                if instruction.opcode == .Modulo {
                    return strings.clone(
                        "resident modulo expects int operands",
                    ), false
                }
                result_float := stack[start].scalar.float_value
                if instruction.opcode == .Subtract && arity == 1 {
                    result_float = -result_float
                }
                for value in stack[start+1:] {
                    operand := value.scalar.float_value
                    #partial switch instruction.opcode {
                    case .Add:      result_float += operand
                    case .Subtract: result_float -= operand
                    case .Multiply: result_float *= operand
                    case .Divide:   result_float /= operand
                    case .Modulo:
                        return strings.clone(
                            "resident modulo expects int operands",
                        ), false
                    case:
                    }
                }
                result.float_value = result_float
            }
            for value in stack[start:] {
                worker_plan_value_release(
                    worker,
                    &owned_values,
                    value,
                )
            }
            resize(&stack, start)
            append(&stack, Worker_Plan_Value{scalar = result})
        case .Not:
            if len(stack) < 1 || stack[len(stack)-1].scalar.kind != .Bool {
                return strings.clone(
                    "resident not expects a bool operand",
                ), false
            }
            stack[len(stack)-1].scalar.int_value =
                0 if stack[len(stack)-1].scalar.int_value != 0 else 1
        case .Equal, .Not_Equal,
             .Less, .Less_Equal, .Greater, .Greater_Equal:
            if len(stack) < 2 {
                return strings.clone(
                    "invalid resident comparison stack",
                ), false
            }
            left := stack[len(stack)-2].scalar
            right := stack[len(stack)-1].scalar
            if left.kind != right.kind ||
               (instruction.opcode != .Equal &&
                instruction.opcode != .Not_Equal &&
                left.kind != .Int && left.kind != .F64) {
                return strings.clone(
                    "invalid resident comparison operands",
                ), false
            }
            compared := false
            if left.kind == .Bool {
                compared = (left.int_value != 0) == (right.int_value != 0)
                if instruction.opcode == .Not_Equal {
                    compared = !compared
                }
            } else if left.kind == .Int {
                #partial switch instruction.opcode {
                case .Equal:         compared = left.int_value == right.int_value
                case .Not_Equal:     compared = left.int_value != right.int_value
                case .Less:          compared = left.int_value < right.int_value
                case .Less_Equal:    compared = left.int_value <= right.int_value
                case .Greater:       compared = left.int_value > right.int_value
                case .Greater_Equal: compared = left.int_value >= right.int_value
                case:
                }
            } else if left.kind == .F64 {
                #partial switch instruction.opcode {
                case .Equal:
                    compared = left.float_value == right.float_value
                case .Not_Equal:
                    compared = left.float_value != right.float_value
                case .Less:
                    compared = left.float_value < right.float_value
                case .Less_Equal:
                    compared = left.float_value <= right.float_value
                case .Greater:
                    compared = left.float_value > right.float_value
                case .Greater_Equal:
                    compared = left.float_value >= right.float_value
                case:
                }
            } else if left.kind == .String {
                left_text := string(left.string_data[:left.string_length])
                right_text := string(right.string_data[:right.string_length])
                compared = left_text == right_text
                if instruction.opcode == .Not_Equal {
                    compared = !compared
                }
            } else {
                return strings.clone(
                    "invalid resident comparison operands",
                ), false
            }
            worker_plan_value_release(
                worker,
                &owned_values,
                stack[len(stack)-2],
            )
            worker_plan_value_release(
                worker,
                &owned_values,
                stack[len(stack)-1],
            )
            resize(&stack, len(stack)-2)
            append(&stack, Worker_Plan_Value{
                scalar = {
                    kind = .Bool,
                    int_value = 1 if compared else 0,
                },
            })
        case .Jump:
            pc = instruction.operand
            continue
        case .Branch_False:
            if len(stack) < 1 || stack[len(stack)-1].scalar.kind != .Bool {
                return strings.clone(
                    "resident branch expects a bool operand",
                ), false
            }
            condition := stack[len(stack)-1].scalar.int_value != 0
            worker_plan_value_release(
                worker,
                &owned_values,
                stack[len(stack)-1],
            )
            resize(&stack, len(stack)-1)
            if !condition {
                pc = instruction.operand
                continue
            }
        case .Short_False, .Short_True:
            if len(stack) < 1 || stack[len(stack)-1].scalar.kind != .Bool {
                return strings.clone(
                    "resident boolean operation expects bool operands",
                ), false
            }
            condition := stack[len(stack)-1].scalar.int_value != 0
            should_jump :=
                (!condition && instruction.opcode == .Short_False) ||
                (condition && instruction.opcode == .Short_True)
            if should_jump {
                pc = instruction.operand
                continue
            }
            worker_plan_value_release(
                worker,
                &owned_values,
                stack[len(stack)-1],
            )
            resize(&stack, len(stack)-1)
        case .Invalid:
            return strings.clone("invalid resident execution opcode"), false
        }
        pc += 1
    }
    if len(stack) != 1 ||
       (plan.result_kind == .Bool && stack[0].scalar.kind != .Bool) ||
       (plan.result_kind == .Int && stack[0].scalar.kind != .Int) ||
       (plan.result_kind == .F64 && stack[0].scalar.kind != .F64) ||
       (plan.result_kind == .String && stack[0].scalar.kind != .String) ||
       (plan.result_kind == .Data && stack[0].scalar.kind != .Data) {
        return strings.clone("invalid resident execution result"), false
    }
    switch plan.result_action {
    case .Rotate_History:
        result_abi := "value:Data" if plan.result_kind == .Data else ""
        if !worker_store_scalar_result(
            worker,
            stack[0].scalar,
            result_abi,
        ) {
            return strings.clone("failed to store resident execution result"), false
        }
    case .Preserve_History:
        if plan.result_kind == .Data {
            return strings.clone("invalid resident execution result action"), false
        }
        rendered := ""
        if stack[0].scalar.kind == .Bool {
            rendered = fmt.aprintf(
                "%v\n",
                stack[0].scalar.int_value != 0,
            )
        } else if stack[0].scalar.kind == .F64 {
            rendered = fmt.aprintf("%v\n", stack[0].scalar.float_value)
        } else if stack[0].scalar.kind == .String {
            value := string(
                stack[0].scalar.string_data[
                    :stack[0].scalar.string_length
                ],
            )
            rendered = fmt.aprintf("%s\n", value)
        } else {
            rendered = fmt.aprintf(
                "%v\n",
                int(stack[0].scalar.int_value),
            )
        }
        defer delete(rendered)
        worker_emit_output(
            rawptr(worker),
            Rendered_Value{
                data = raw_data(rendered),
                length = len(rendered),
            },
        )
    case .Invalid:
        return strings.clone("invalid resident execution result action"), false
    }
    return "", true
}

worker_invoke_scalar :: proc(
    worker: ^Worker,
    name,
    signature: string,
    args: []Scalar_Value,
) -> bool {
    invoke_slot := worker_find_scalar_invoke(worker, name, signature)
    if invoke_slot == nil {
        return false
    }
    result, aborted, invoked := worker_call_scalar_invoke(
        worker,
        invoke_slot,
        args,
    )
    if !invoked {
        return false
    }
    if aborted {
        worker_release_owned_scalar_value(worker, result)
        return true
    }
    return worker_store_scalar_result(worker, result, invoke_slot.result_abi)
}

worker_emit_output :: proc "c" (
    context_ptr: rawptr,
    value: Rendered_Value,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    context.allocator = worker.allocator
    rendered := string(value.data[:value.length])
    if worker.emit_output_to_stdout {
        fmt.print(rendered)
        _ = os.flush(os.stdout)
        return
    }
    delete(worker.output)
    worker.output = strings.clone(rendered)
}

worker_emit_stream_output :: proc "c" (
    context_ptr: rawptr,
    value: Rendered_Value,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    context.allocator = worker.allocator
    rendered := string(value.data[:value.length])
    if worker.emit_output_to_stdout {
        fmt.print("KVIST_REPL_STREAM_OUTPUT\t")
        worker_write_hex(rendered)
        fmt.println()
        _ = os.flush(os.stdout)
        return
    }
    if worker.attached_output_handler == nil {
        return
    }
    callback_started := time.tick_now()
    worker.attached_output_handler(
        worker.attached_output_ctx,
        "stdout",
        rendered,
    )
    if worker.trace_enabled {
        callback_duration := time.tick_since(callback_started)
        worker.trace_started_at =
            time.tick_add(worker.trace_started_at, callback_duration)
        worker.trace_last_at =
            time.tick_add(worker.trace_last_at, callback_duration)
    }
}

worker_take_output :: proc(worker: ^Worker) -> string {
    return worker.output
}

worker_write_hex :: proc(value: string) {
    for byte in transmute([]byte)value {
        fmt.printf("%02x", byte)
    }
}

worker_hex_nibble :: proc(byte: u8) -> (u8, bool) {
    if byte >= '0' && byte <= '9' {
        return byte-'0', true
    }
    if byte >= 'a' && byte <= 'f' {
        return byte-'a'+10, true
    }
    if byte >= 'A' && byte <= 'F' {
        return byte-'A'+10, true
    }
    return 0, false
}

worker_hex_decode :: proc(encoded: string) -> (string, bool) {
    if len(encoded)%2 != 0 {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for i := 0; i < len(encoded); i += 2 {
        high, high_ok := worker_hex_nibble(encoded[i])
        low, low_ok := worker_hex_nibble(encoded[i+1])
        if !high_ok || !low_ok {
            return "", false
        }
        strings.write_byte(&builder, (high << 4) | low)
    }
    return strings.clone(strings.to_string(builder)), true
}

worker_page_emit :: proc "c" (
    _: rawptr,
    index: int,
    key: Rendered_Value,
    value: Rendered_Value,
) {
    context = runtime.default_context()
    rendered_key := string(key.data[:key.length])
    rendered := string(value.data[:value.length])
    fmt.printf("KVIST_REPL_DEBUG_PAGE_ITEM\t%d\t", index)
    worker_write_hex(rendered_key)
    fmt.print("\t")
    worker_write_hex(rendered)
    fmt.println()
}

Debug_Page_State :: struct {
    collections: ^[dynamic]Debug_Collection,
    parent_path: string,
    owned_contexts: ^[dynamic]rawptr,
}

worker_collection_emit :: proc "c" (
    ctx: rawptr,
    relative_path: Rendered_Value,
    shape: Rendered_Value,
    element_type: Rendered_Value,
    key_type: Rendered_Value,
    value_type: Rendered_Value,
    collection_ctx: rawptr,
    render_page: rawptr,
    copy_context_size: int,
    copy_context_align: int,
) {
    context = runtime.default_context()
    state := transmute(^Debug_Page_State)ctx
    relative := string(relative_path.data[:relative_path.length])
    full_path := fmt.aprintf("%s%s", state.parent_path, relative)
    for collection in state.collections^ {
        path := string(collection.path.data[:collection.path.length])
        if path == full_path {
            delete(full_path)
            return
        }
    }
    shape_text :=
        strings.clone(string(shape.data[:shape.length]))
    element_type_text :=
        strings.clone(string(element_type.data[:element_type.length]))
    key_type_text :=
        strings.clone(string(key_type.data[:key_type.length]))
    value_type_text :=
        strings.clone(string(value_type.data[:value_type.length]))
    retained_context := collection_ctx
    if copy_context_size > 0 {
        copied, alloc_err :=
            mem.alloc(copy_context_size, copy_context_align)
        if alloc_err != nil {
            delete(full_path)
            delete(shape_text)
            delete(element_type_text)
            delete(key_type_text)
            delete(value_type_text)
            return
        }
        mem.copy(copied, collection_ctx, copy_context_size)
        append(state.owned_contexts, copied)
        retained_context = copied
    }
    descriptor := Debug_Collection{
        path = Rendered_Value{
            data = raw_data(full_path),
            length = len(full_path),
        },
        shape = Rendered_Value{
            data = raw_data(shape_text),
            length = len(shape_text),
        },
        element_type = Rendered_Value{
            data = raw_data(element_type_text),
            length = len(element_type_text),
        },
        key_type = Rendered_Value{
            data = raw_data(key_type_text),
            length = len(key_type_text),
        },
        value_type = Rendered_Value{
            data = raw_data(value_type_text),
            length = len(value_type_text),
        },
        collection_ctx = retained_context,
        render_page = transmute(Render_Page)render_page,
    }
    append(state.collections, descriptor)
    fmt.printf(
        "KVIST_REPL_DEBUG_COLLECTION\t%d\t",
        len(state.collections^)-1,
    )
    worker_write_hex(full_path)
    fmt.print("\t")
    worker_write_hex(shape_text)
    fmt.print("\t")
    worker_write_hex(element_type_text)
    fmt.print("\t")
    worker_write_hex(key_type_text)
    fmt.print("\t")
    worker_write_hex(value_type_text)
    fmt.println()
}

worker_step_should_pause :: proc(worker: ^Worker) -> bool {
    if !worker.step_armed {
        return false
    }
    switch worker.step_mode {
    case .Into:
        return true
    case .Over:
        return worker.frame_depth <= worker.step_depth
    case .Out:
        return worker.frame_depth < worker.step_depth
    }
    return false
}

worker_debug_flags :: proc "c" (worker_ptr: rawptr) -> u32 {
    context = runtime.default_context()
    worker := transmute(^Worker)worker_ptr
    flags := u32(0)
    if worker_step_should_pause(worker) {
        flags |= DEBUG_FLAG_PAUSE
    }
    if worker.trace_enabled && worker.trace_remaining > 0 {
        flags |= DEBUG_FLAG_TRACE
    } else if worker.trace_enabled &&
              !worker.trace_limit_reported {
        elapsed_ns :=
            time.duration_nanoseconds(
                time.tick_since(worker.trace_started_at),
            )
        if worker.attached_trace_handler != nil {
            callback_started := time.tick_now()
            worker.attached_trace_handler(
                worker.attached_trace_ctx,
                "trace-limit",
                "",
                worker.frame_depth,
                int(elapsed_ns),
                0,
            )
            callback_duration := time.tick_since(callback_started)
            worker.trace_started_at =
                time.tick_add(worker.trace_started_at, callback_duration)
            worker.trace_last_at =
                time.tick_add(worker.trace_last_at, callback_duration)
        } else {
            fmt.printf("%s\t%d\n", TRACE_LIMIT_MARKER, elapsed_ns)
            _ = os.flush(os.stdout)
        }
        worker.trace_limit_reported = true
    }
    if worker.trace_enabled &&
       worker.trace_remaining > 0 &&
       worker.trace_values_enabled &&
       worker.trace_values_remaining > 0 {
        flags |= DEBUG_FLAG_TRACE_VALUES
    } else if worker.trace_enabled &&
              worker.trace_remaining > 0 &&
              worker.trace_values_enabled &&
              !worker.trace_values_limit_reported {
        if worker.attached_trace_handler != nil {
            callback_started := time.tick_now()
            worker.attached_trace_handler(
                worker.attached_trace_ctx,
                "trace-values-limit",
                "",
                worker.frame_depth,
                0,
                0,
            )
            callback_duration := time.tick_since(callback_started)
            worker.trace_started_at =
                time.tick_add(worker.trace_started_at, callback_duration)
            worker.trace_last_at =
                time.tick_add(worker.trace_last_at, callback_duration)
        } else {
            fmt.println(TRACE_VALUES_LIMIT_MARKER)
            _ = os.flush(os.stdout)
        }
        worker.trace_values_limit_reported = true
    }
    return flags
}

worker_trace_point :: proc "c" (
    worker_ptr: rawptr,
    trace_id_ptr: cstring,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)worker_ptr
    if !worker.trace_enabled || worker.trace_remaining <= 0 {
        return
    }
    worker.trace_remaining -= 1
    now := time.tick_now()
    elapsed_ns :=
        time.duration_nanoseconds(
            time.tick_diff(worker.trace_started_at, now),
        )
    delta_ns :=
        time.duration_nanoseconds(
            time.tick_diff(worker.trace_last_at, now),
        )
    worker.trace_last_at = now
    if worker.attached_trace_handler != nil {
        callback_started := time.tick_now()
        worker.attached_trace_handler(
            worker.attached_trace_ctx,
            "trace",
            string(trace_id_ptr),
            worker.frame_depth,
            int(elapsed_ns),
            int(delta_ns),
        )
        callback_duration := time.tick_since(callback_started)
        worker.trace_started_at =
            time.tick_add(worker.trace_started_at, callback_duration)
        worker.trace_last_at =
            time.tick_add(worker.trace_last_at, callback_duration)
    } else {
        fmt.printf(
            "KVIST_REPL_TRACE\t%s\t%d\t%d\t%d\n",
            string(trace_id_ptr),
            worker.frame_depth,
            elapsed_ns,
            delta_ns,
        )
        _ = os.flush(os.stdout)
    }
}

worker_trace_values :: proc "c" (
    worker_ptr: rawptr,
    trace_id_ptr: cstring,
    values: [^]Rendered_Value,
    value_count: int,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)worker_ptr
    if !worker.trace_values_enabled ||
       worker.trace_values_remaining <= 0 {
        return
    }
    worker.trace_values_remaining -= 1
    if worker.attached_trace_values_handler != nil {
        callback_started := time.tick_now()
        worker.attached_trace_values_handler(
            worker.attached_trace_values_ctx,
            string(trace_id_ptr),
            values,
            value_count,
        )
        callback_duration := time.tick_since(callback_started)
        worker.trace_started_at =
            time.tick_add(worker.trace_started_at, callback_duration)
        worker.trace_last_at =
            time.tick_add(worker.trace_last_at, callback_duration)
        return
    }
    fmt.printf(
        "KVIST_REPL_TRACE_VALUES\t%s\t%d",
        string(trace_id_ptr),
        value_count,
    )
    for value in values[:value_count] {
        fmt.print("\t")
        worker_write_hex(string(value.data[:value.length]))
    }
    fmt.println()
    _ = os.flush(os.stdout)
}

worker_condition :: proc "c" (
    worker_ptr: rawptr,
    pause_id_ptr: cstring,
    condition_type: Rendered_Value,
    message: Rendered_Value,
    data: Rendered_Value,
    value_type: Rendered_Value,
    restart_flags: u32,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)worker_ptr
    if worker.attached_condition_handler != nil {
        worker.attached_condition_handler(
            worker.attached_condition_ctx,
            string(pause_id_ptr),
            string(condition_type.data[:condition_type.length]),
            string(message.data[:message.length]),
            string(data.data[:data.length]),
            string(value_type.data[:value_type.length]),
            restart_flags,
        )
        return
    }
    fmt.printf(
        "KVIST_REPL_CONDITION\t%s\t",
        string(pause_id_ptr),
    )
    worker_write_hex(
        string(condition_type.data[:condition_type.length]),
    )
    fmt.print("\t")
    worker_write_hex(string(message.data[:message.length]))
    fmt.print("\t")
    worker_write_hex(string(data.data[:data.length]))
    fmt.print("\t")
    if value_type.length == 0 {
        fmt.print("-")
    } else {
        worker_write_hex(string(value_type.data[:value_type.length]))
    }
    fmt.printf("\t%d", restart_flags)
    fmt.println()
    _ = os.flush(os.stdout)
}

worker_enter_frame :: proc "c" (worker_ptr: rawptr) {
    context = runtime.default_context()
    worker := transmute(^Worker)worker_ptr
    worker.frame_depth += 1
}

worker_leave_frame :: proc "c" (worker_ptr: rawptr) {
    context = runtime.default_context()
    worker := transmute(^Worker)worker_ptr
    worker.frame_depth = max(worker.frame_depth-1, 0)
}

worker_abort_requested :: proc "c" (worker_ptr: rawptr) -> bool {
    worker := transmute(^Worker)worker_ptr
    if !worker.abort_requested ||
       worker.frame_depth > worker.abort_unwind_depth {
        return false
    }
    worker.abort_unwind_depth = worker.frame_depth-1
    return true
}

worker_pause :: proc "c" (
    worker_ptr: rawptr,
    pause_id_ptr: cstring,
    values: [^]Rendered_Value,
    value_count: int,
    collections: [^]Debug_Collection,
    collection_count: int,
    required: bool,
    restart_selection: ^Restart_Selection,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)worker_ptr
    if !required && !worker_step_should_pause(worker) {
        return
    }
    delete(worker.restart_name)
    worker.restart_name = ""
    worker.restart_value = ""
    if restart_selection != nil {
        restart_selection^ = {}
    }
    worker.step_armed = false
    if worker.attached_pause_handler != nil {
        worker.attached_pause_handler(
            worker.attached_pause_ctx,
            string(pause_id_ptr),
            values,
            value_count,
            collections,
            collection_count,
            restart_selection,
        )
        return
    }
    available := make(
        [dynamic]Debug_Collection,
        0,
        collection_count,
    )
    defer delete(available)
    owned_contexts: [dynamic]rawptr
    defer {
        for owned_context in owned_contexts {
            _ = mem.free(owned_context)
        }
        delete(owned_contexts)
    }
    for i in 0..<collection_count {
        append(&available, collections[i])
    }
    defer {
        for i in collection_count..<len(available) {
            collection := available[i]
            delete(string(
                collection.path.data[:collection.path.length],
            ))
            delete(string(
                collection.shape.data[:collection.shape.length],
            ))
            delete(string(
                collection.element_type.data[
                    :collection.element_type.length
                ],
            ))
            delete(string(
                collection.key_type.data[:collection.key_type.length],
            ))
            delete(string(
                collection.value_type.data[
                    :collection.value_type.length
                ],
            ))
        }
    }
    fmt.printf("KVIST_REPL_PAUSED\t%s", string(pause_id_ptr))
    for i in 0 ..< value_count {
        rendered := string(values[i].data[:values[i].length])
        fmt.print("\t")
        worker_write_hex(rendered)
    }
    if collection_count > 0 {
        fmt.print("\t__collections__")
        for i in 0..<collection_count {
            path := string(
                collections[i].path.data[:collections[i].path.length],
            )
            element_type := string(
                collections[i].element_type.data[
                    :collections[i].element_type.length
                ],
            )
            shape := string(
                collections[i].shape.data[:collections[i].shape.length],
            )
            key_type := string(
                collections[i].key_type.data[:collections[i].key_type.length],
            )
            value_type := string(
                collections[i].value_type.data[
                    :collections[i].value_type.length
                ],
            )
            fmt.print("\t")
            worker_write_hex(path)
            fmt.print("=")
            worker_write_hex(shape)
            fmt.print("=")
            worker_write_hex(element_type)
            fmt.print("=")
            worker_write_hex(key_type)
            fmt.print("=")
            worker_write_hex(value_type)
        }
    }
    fmt.println()
    _ = os.flush(os.stdout)

    if worker.input_reader == nil {
        return
    }
    for {
        command, err :=
            bufio.reader_read_string(worker.input_reader, '\n')
        if len(command) == 0 && err != nil {
            return
        }
        trimmed := strings.trim_space(command)
        should_continue := trimmed == "__continue__"
        should_step_into :=
            trimmed == "__step__" ||
            trimmed == "__step_into__"
        should_step_over := trimmed == "__step_over__"
        should_step_out := trimmed == "__step_out__"
        should_step :=
            should_step_into ||
            should_step_over ||
            should_step_out
        should_abort := trimmed == "__abort__"
        if should_abort {
            worker.abort_requested = true
            worker.abort_unwind_depth = worker.frame_depth
            worker.step_armed = false
        }
        should_restart := false
        if strings.has_prefix(trimmed, "__restart__\t") {
            fields := strings.split(
                trimmed,
                "\t",
                context.temp_allocator,
            )
            if len(fields) == 3 {
                restart_name, name_ok :=
                    worker_hex_decode(fields[1])
                restart_value := ""
                value_ok := fields[2] == "-"
                if value_ok {
                    restart_value = strings.clone("")
                } else {
                    restart_value, value_ok =
                        worker_hex_decode(fields[2])
                }
                if name_ok && value_ok {
                    worker.restart_name = restart_name
                    append(&worker.restart_payloads, restart_value)
                    worker.restart_value =
                        worker.restart_payloads[
                            len(worker.restart_payloads)-1
                        ]
                    should_restart = true
                } else {
                    delete(restart_name)
                    delete(restart_value)
                }
            }
        }
        if should_step {
            worker.step_armed = true
            worker.step_depth = worker.frame_depth
            if should_step_over {
                worker.step_mode = .Over
            } else if should_step_out {
                worker.step_mode = .Out
            } else {
                worker.step_mode = .Into
            }
        }
        if strings.has_prefix(trimmed, "__debug_page__\t") {
            fields := strings.split(trimmed, "\t", context.temp_allocator)
            if len(fields) == 4 {
                collection_index, index_ok :=
                    strconv.parse_int(fields[1])
                offset, offset_ok := strconv.parse_int(fields[2])
                limit, limit_ok := strconv.parse_int(fields[3])
                if index_ok && offset_ok && limit_ok &&
                   collection_index >= 0 &&
                   collection_index < len(available) &&
                   offset >= 0 && limit > 0 {
                    descriptor := available[collection_index]
                    parent_path := string(
                        descriptor.path.data[:descriptor.path.length],
                    )
                    page_state := Debug_Page_State{
                        collections = &available,
                        parent_path = parent_path,
                        owned_contexts = &owned_contexts,
                    }
                    total := descriptor.render_page(
                        descriptor.collection_ctx,
                        offset,
                        limit,
                        rawptr(&page_state),
                        worker_page_emit,
                        worker_collection_emit,
                    )
                    fmt.printf(
                        "KVIST_REPL_DEBUG_PAGE_END\t%d\n",
                        total,
                    )
                    _ = os.flush(os.stdout)
                }
            }
        }
        if strings.has_prefix(trimmed, "__nested__\t") {
            fields := strings.split(
                trimmed,
                "\t",
                context.temp_allocator,
            )
            if len(fields) == 2 {
                path, path_ok := worker_hex_decode(fields[1])
                if path_ok {
                    message, loaded :=
                        worker_load_and_run_nested(worker, path)
                    if loaded {
                        fmt.println("KVIST_REPL_WORKER\tok")
                    } else {
                        fmt.printf(
                            "KVIST_REPL_WORKER\terror\t%s\n",
                            message,
                        )
                        delete(message)
                    }
                } else {
                    fmt.println(
                        "KVIST_REPL_WORKER\terror\tinvalid nested library path",
                    )
                }
                delete(path)
            } else {
                fmt.println(
                    "KVIST_REPL_WORKER\terror\tinvalid nested worker command",
                )
            }
            _ = os.flush(os.stdout)
        }
        delete(command)
        if should_continue || should_step || should_restart || should_abort {
            if restart_selection != nil && should_restart {
                restart_selection.name = Rendered_Value{
                    data = raw_data(worker.restart_name),
                    length = len(worker.restart_name),
                }
                restart_selection.value = Rendered_Value{
                    data = raw_data(worker.restart_value),
                    length = len(worker.restart_value),
                }
            }
            return
        }
    }
}

worker_ensure_host_api :: proc(worker: ^Worker) {
    worker.host_api = Host_API{
        ctx = rawptr(worker),
        allocator = runtime.Allocator{
            procedure = worker_managed_allocator_proc,
            data = rawptr(worker),
        },
        register_proc = worker_register_proc,
        lookup_proc = worker_lookup_proc,
        register_result = worker_register_result,
        render_scalar_result = worker_render_scalar_result,
        register_scalar_invoke = worker_register_scalar_invoke,
        register_state = worker_register_state,
        debug_flags = worker_debug_flags,
        trace_point = worker_trace_point,
        trace_values = worker_trace_values,
        condition = worker_condition,
        emit_output = worker_emit_output,
        emit_stream_output = worker_emit_stream_output,
        enter_frame = worker_enter_frame,
        leave_frame = worker_leave_frame,
        pause = worker_pause,
        abort_requested = worker_abort_requested,
        transfer_result_allocation =
            worker_transfer_result_allocation,
        retain_result_allocation =
            worker_retain_result_allocation,
        transfer_binding_allocation =
            worker_transfer_binding_allocation,
        retain_binding_allocation =
            worker_retain_binding_allocation,
        condition_handler_push = worker_condition_handler_push,
        condition_handler_pop = worker_condition_handler_pop,
        condition_handler_count = worker_condition_handler_count,
        condition_handler_kind_at = worker_condition_handler_kind_at,
        condition_handler_at = worker_condition_handler_at,
    }
}

worker_condition_handler_push :: proc "c" (
    context_ptr: rawptr,
    kind_value: Rendered_Value,
    handler: rawptr,
) {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    context.allocator = worker.allocator
    assert(handler != nil, "condition handler must not be nil")
    assert(len(worker.condition_handlers) < 64, "condition handler stack exhausted")
    kind := string(kind_value.data[:kind_value.length])
    append(&worker.condition_handlers, Condition_Handler_Entry{
        kind = strings.clone(kind),
        handler = handler,
    })
}

worker_condition_handler_pop :: proc "c" (context_ptr: rawptr) {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    context.allocator = worker.allocator
    assert(len(worker.condition_handlers) > 0, "condition handler stack underflow")
    index := len(worker.condition_handlers) - 1
    delete(worker.condition_handlers[index].kind)
    pop(&worker.condition_handlers)
}

worker_condition_handler_count :: proc "c" (context_ptr: rawptr) -> int {
    worker := transmute(^Worker)context_ptr
    return len(worker.condition_handlers)
}

worker_condition_handler_kind_at :: proc "c" (
    context_ptr: rawptr,
    index: int,
) -> Rendered_Value {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    assert(index >= 0 && index < len(worker.condition_handlers))
    kind := worker.condition_handlers[index].kind
    return Rendered_Value{data = raw_data(kind), length = len(kind)}
}

worker_condition_handler_at :: proc "c" (
    context_ptr: rawptr,
    index: int,
) -> rawptr {
    context = runtime.default_context()
    worker := transmute(^Worker)context_ptr
    assert(index >= 0 && index < len(worker.condition_handlers))
    return worker.condition_handlers[index].handler
}

worker_transfer_result_allocation :: proc "c" (
    context_ptr: rawptr,
    memory: rawptr,
) {
    if context_ptr == nil || memory == nil {
        return
    }
    worker := (^Worker)(context_ptr)
    context = runtime.default_context()
    context.allocator = worker.allocator
    sync.mutex_guard(&worker.managed_allocation_mutex)
    allocation, found := worker.managed_allocations[memory]
    if !found {
        return
    }
    if allocation.owner_kind == .Result &&
       allocation.owner_generation == len(worker.generations) {
        return
    }
    worker.next_managed_transfer += 1
    append(&worker.managed_transfers, Worker_Managed_Transfer{
        sequence = worker.next_managed_transfer,
        allocation = allocation.allocation,
        generation = len(worker.generations),
        owner_from_kind = allocation.owner_kind,
        owner_from_generation = allocation.owner_generation,
        owner_from_name = strings.clone(allocation.owner_name),
        owner_to_kind = .Result,
        owner_to_generation = len(worker.generations),
        action = .Transferred,
    })
    allocation.owner_kind = .Result
    allocation.owner_generation = len(worker.generations)
    delete(allocation.owner_name, worker.allocator)
    allocation.owner_name = ""
    worker.managed_allocations[memory] = allocation
}

worker_retain_result_allocation :: proc "c" (
    context_ptr: rawptr,
    memory: rawptr,
) {
    if context_ptr == nil || memory == nil {
        return
    }
    worker := (^Worker)(context_ptr)
    context = runtime.default_context()
    context.allocator = worker.allocator
    sync.mutex_guard(&worker.managed_allocation_mutex)
    allocation, found := worker.managed_allocations[memory]
    if !found {
        return
    }
    generation := len(worker.generations)
    if allocation.owner_kind == .Result &&
       allocation.owner_generation == generation {
        return
    }
    for retained_generation in
        allocation.retained_result_generations {
        if retained_generation == generation {
            return
        }
    }
    append(
        &allocation.retained_result_generations,
        generation,
    )
    worker.next_managed_transfer += 1
    append(&worker.managed_transfers, Worker_Managed_Transfer{
        sequence = worker.next_managed_transfer,
        allocation = allocation.allocation,
        generation = generation,
        owner_from_kind = allocation.owner_kind,
        owner_from_generation = allocation.owner_generation,
        owner_from_name = strings.clone(allocation.owner_name),
        owner_to_kind = .Result,
        owner_to_generation = generation,
        action = .Retained,
    })
    worker.managed_allocations[memory] = allocation
}

worker_transfer_binding_allocation :: proc "c" (
    context_ptr: rawptr,
    name_ptr: cstring,
    memory: rawptr,
) {
    if context_ptr == nil || name_ptr == nil || memory == nil {
        return
    }
    worker := (^Worker)(context_ptr)
    context = runtime.default_context()
    context.allocator = worker.allocator
    name := string(name_ptr)
    generation := len(worker.generations)
    sync.mutex_guard(&worker.managed_allocation_mutex)
    allocation, found := worker.managed_allocations[memory]
    if !found {
        return
    }
    if allocation.owner_kind == .Binding &&
       allocation.owner_generation == generation &&
       allocation.owner_name == name {
        return
    }
    worker.next_managed_transfer += 1
    append(&worker.managed_transfers, Worker_Managed_Transfer{
        sequence = worker.next_managed_transfer,
        allocation = allocation.allocation,
        generation = generation,
        owner_from_kind = allocation.owner_kind,
        owner_from_generation = allocation.owner_generation,
        owner_from_name = strings.clone(allocation.owner_name),
        owner_to_kind = .Binding,
        owner_to_generation = generation,
        owner_to_name = strings.clone(name),
        action = .Transferred,
    })
    allocation.owner_kind = .Binding
    allocation.owner_generation = generation
    delete(allocation.owner_name, worker.allocator)
    allocation.owner_name = strings.clone(name)
    worker.managed_allocations[memory] = allocation
}

worker_retain_binding_allocation :: proc "c" (
    context_ptr: rawptr,
    name_ptr: cstring,
    memory: rawptr,
) {
    if context_ptr == nil || name_ptr == nil || memory == nil {
        return
    }
    worker := (^Worker)(context_ptr)
    context = runtime.default_context()
    context.allocator = worker.allocator
    name := string(name_ptr)
    generation := len(worker.generations)
    sync.mutex_guard(&worker.managed_allocation_mutex)
    allocation, found := worker.managed_allocations[memory]
    if !found {
        return
    }
    if allocation.owner_kind == .Binding &&
       allocation.owner_generation == generation &&
       allocation.owner_name == name {
        return
    }
    for owner in allocation.retained_binding_owners {
        if owner.generation == generation &&
           owner.name == name {
            return
        }
    }
    append(
        &allocation.retained_binding_owners,
        Worker_Managed_Binding_Owner{
            name = strings.clone(name),
            generation = generation,
        },
    )
    worker.next_managed_transfer += 1
    append(&worker.managed_transfers, Worker_Managed_Transfer{
        sequence = worker.next_managed_transfer,
        allocation = allocation.allocation,
        generation = generation,
        owner_from_kind = allocation.owner_kind,
        owner_from_generation = allocation.owner_generation,
        owner_from_name = strings.clone(allocation.owner_name),
        owner_to_kind = .Binding,
        owner_to_generation = generation,
        owner_to_name = strings.clone(name),
        action = .Retained,
    })
    worker.managed_allocations[memory] = allocation
}

worker_checkpoint_find :: proc(worker: ^Worker, name: string) -> int {
    for checkpoint, index in worker.checkpoints {
        if checkpoint.name == name {
            return index
        }
    }
    return -1
}

worker_checkpoint_inventory_count :: proc(worker: ^Worker) -> int {
    if worker == nil {
        return 0
    }
    return len(worker.checkpoints)
}

worker_checkpoint_inventory_entry :: proc(
    worker: ^Worker,
    index: int,
) -> (name: string, bindings: int, ok: bool) {
    if worker == nil || index < 0 || index >= len(worker.checkpoints) {
        return "", 0, false
    }
    checkpoint := &worker.checkpoints[index]
    return checkpoint.name, len(checkpoint.entries), true
}

worker_allocation_stats :: proc(
    worker: ^Worker,
) -> Worker_Allocation_Stats {
    if worker == nil {
        return {}
    }
    return Worker_Allocation_Stats{
        live_allocations = worker.checkpoint_live_allocations,
        live_bytes = worker.checkpoint_live_bytes,
        total_allocations = worker.checkpoint_total_allocations,
        total_allocated_bytes =
            worker.checkpoint_total_allocated_bytes,
        total_frees = worker.checkpoint_total_frees,
        total_freed_bytes = worker.checkpoint_total_freed_bytes,
        managed_live_allocations =
            len(worker.generation_allocator.allocation_map) if
                worker.generation_allocator_initialized else 0,
        managed_live_bytes =
            int(worker.generation_allocator.current_memory_allocated) if
                worker.generation_allocator_initialized else 0,
        managed_peak_bytes =
            int(worker.generation_allocator.peak_memory_allocated) if
                worker.generation_allocator_initialized else 0,
        managed_total_allocations =
            int(worker.generation_allocator.total_allocation_count) if
                worker.generation_allocator_initialized else 0,
        managed_total_allocated_bytes =
            int(worker.generation_allocator.total_memory_allocated) if
                worker.generation_allocator_initialized else 0,
        managed_total_frees =
            int(worker.generation_allocator.total_free_count) if
                worker.generation_allocator_initialized else 0,
        managed_total_freed_bytes =
            int(worker.generation_allocator.total_memory_freed) if
                worker.generation_allocator_initialized else 0,
    }
}

worker_managed_allocation_inventory :: proc(
    worker: ^Worker,
    allocator := context.allocator,
) -> [dynamic]Worker_Managed_Allocation {
    sync.mutex_guard(&worker.managed_allocation_mutex)
    allocations := make(
        [dynamic]Worker_Managed_Allocation,
        0,
        len(worker.managed_allocations),
        allocator,
    )
    for _, allocation in worker.managed_allocations {
        append(&allocations, allocation)
    }
    // Stable protocol order without exposing native addresses.
    for index in 1..<len(allocations) {
        cursor := index
        for cursor > 0 &&
            allocations[cursor-1].allocation >
                allocations[cursor].allocation {
            allocations[cursor-1], allocations[cursor] =
                allocations[cursor], allocations[cursor-1]
            cursor -= 1
        }
    }
    return allocations
}

worker_managed_transfer_history :: proc(
    worker: ^Worker,
    allocator := context.allocator,
) -> [dynamic]Worker_Managed_Transfer {
    sync.mutex_guard(&worker.managed_allocation_mutex)
    transfers := make(
        [dynamic]Worker_Managed_Transfer,
        0,
        len(worker.managed_transfers),
        allocator,
    )
    append(&transfers, ..worker.managed_transfers[:])
    return transfers
}

worker_checkpoint_free_snapshot :: proc(
    worker: ^Worker,
    entry: ^Checkpoint_Entry,
) {
    if entry == nil || entry.snapshot == nil {
        return
    }
    _ = mem.free(entry.snapshot)
    worker.checkpoint_live_allocations -= 1
    worker.checkpoint_live_bytes -= entry.size
    worker.checkpoint_total_frees += 1
    worker.checkpoint_total_freed_bytes += entry.size
    entry.snapshot = nil
}

worker_checkpoint_capture :: proc(
    worker: ^Worker,
    name: string,
) -> (count: int, message: string, ok: bool) {
    if name == "" {
        return 0, strings.clone("checkpoint name must not be empty"), false
    }
    checkpoint := Checkpoint{name = strings.clone(name)}
    for slot in worker.state_slots {
        if slot.clone == nil || slot.restore == nil {
            continue
        }
        snapshot, alloc_err := mem.alloc(slot.size, slot.align)
        if alloc_err != nil {
            delete(checkpoint.name)
            for &entry in checkpoint.entries {
                delete(entry.name)
                delete(entry.signature)
                worker_checkpoint_free_snapshot(
                    worker,
                    &entry,
                )
            }
            delete(checkpoint.entries)
            return 0,
                   strings.clone("failed to snapshot mutable REPL state"),
                   false
        }
        worker.checkpoint_live_allocations += 1
        worker.checkpoint_live_bytes += slot.size
        worker.checkpoint_total_allocations += 1
        worker.checkpoint_total_allocated_bytes += slot.size
        slot.clone(snapshot)
        append(&checkpoint.entries, Checkpoint_Entry{
            name = strings.clone(slot.name),
            signature = strings.clone(slot.signature),
            snapshot = snapshot,
            size = slot.size,
        })
    }
    index := worker_checkpoint_find(worker, name)
    if index >= 0 {
        old := &worker.checkpoints[index]
        delete(old.name)
        for &entry in old.entries {
            delete(entry.name)
            delete(entry.signature)
            worker_checkpoint_free_snapshot(worker, &entry)
        }
        delete(old.entries)
        old^ = checkpoint
    } else {
        append(&worker.checkpoints, checkpoint)
    }
    return len(checkpoint.entries), "", true
}

worker_checkpoint_restore :: proc(
    worker: ^Worker,
    name: string,
) -> (count: int, message: string, ok: bool) {
    index := worker_checkpoint_find(worker, name)
    if index < 0 {
        return 0, fmt.aprintf("unknown checkpoint %q", name), false
    }
    checkpoint := &worker.checkpoints[index]
    // Validate the complete restore set first. No cell changes until every
    // captured binding has an exactly compatible current codec.
    compatible: [dynamic]^State_Slot
    defer delete(compatible)
    for &entry in checkpoint.entries {
        current: ^State_Slot
        for &slot in worker.state_slots {
            if slot.name == entry.name {
                current = &slot
                break
            }
        }
        if current == nil {
            return 0,
                   fmt.aprintf(
                       "checkpoint binding %q is no longer available",
                       entry.name,
                   ),
                   false
        }
        if current.signature != entry.signature {
            return 0,
                   fmt.aprintf(
                       "checkpoint binding %q changed type or layout",
                       entry.name,
                   ),
                   false
        }
        append(&compatible, current)
    }
    for entry, entry_index in checkpoint.entries {
        compatible[entry_index].restore(entry.snapshot)
    }
    return len(checkpoint.entries), "", true
}

worker_checkpoint_drop :: proc(
    worker: ^Worker,
    name: string,
) -> (message: string, ok: bool) {
    index := worker_checkpoint_find(worker, name)
    if index < 0 {
        return fmt.aprintf("unknown checkpoint %q", name), false
    }
    checkpoint := &worker.checkpoints[index]
    delete(checkpoint.name)
    for &entry in checkpoint.entries {
        delete(entry.name)
        delete(entry.signature)
        worker_checkpoint_free_snapshot(worker, &entry)
    }
    delete(checkpoint.entries)
    unordered_remove(&worker.checkpoints, index)
    return "", true
}

worker_trace_next :: proc(
    worker: ^Worker,
    limit: int,
    value_limit := 0,
) {
    worker.trace_enabled = true
    worker.trace_remaining = max(limit, 1)
    worker.trace_limit_reported = false
    worker.trace_values_enabled = value_limit > 0
    worker.trace_values_remaining = max(value_limit, 0)
    worker.trace_values_limit_reported = false
}

worker_delete :: proc(worker: ^Worker) {
    // Generations are intentionally append-only while the worker is alive.
    // Reset and process exit are the reclamation boundaries.
    incremental_llvm_backend_delete(&worker.incremental_backend)
    for generation in worker.generations {
        if generation.__handle != nil {
            _ = dynlib.unload_library(generation.__handle)
        }
        delete(generation.path)
    }
    delete(worker.generations)
    for slot in worker.proc_slots {
        delete(slot.name)
        delete(slot.signature)
    }
    delete(worker.proc_slots)
    for slot in worker.scalar_invoke_slots {
        delete(slot.name)
        delete(slot.signature)
        delete(slot.result_abi)
    }
    delete(worker.scalar_invoke_slots)
    for value in worker.direct_string_results {
        delete(value)
    }
    for slot in worker.state_slots {
        delete(slot.name)
        delete(slot.signature)
    }
    delete(worker.state_slots)
    for checkpoint in worker.checkpoints {
        delete(checkpoint.name)
        for &entry in checkpoint.entries {
            delete(entry.name)
            delete(entry.signature)
            worker_checkpoint_free_snapshot(worker, &entry)
        }
        delete(checkpoint.entries)
    }
    delete(worker.checkpoints)
    for slot in worker.result_slots {
        delete(slot.name)
        delete(slot.signature)
    }
    for handler in worker.condition_handlers {
        delete(handler.kind)
    }
    delete(worker.condition_handlers)
    delete(worker.restart_name)
    for payload in worker.restart_payloads {
        delete(payload)
    }
    delete(worker.restart_payloads)
    delete(worker.output)
    if worker.generation_allocator_initialized {
        // Process exit and attached-session reset are hard reclamation
        // boundaries. Generated values need not remain individually
        // destructible once every generation has been unloaded, but their
        // tracked backing blocks must still be returned to the host.
        for _, entry in worker.generation_allocator.allocation_map {
            _ = mem.free(
                entry.memory,
                worker.generation_allocator.backing,
            )
        }
        for _, &allocation in worker.managed_allocations {
            worker_managed_allocation_metadata_delete(
                &allocation,
                worker.allocator,
            )
        }
        for transfer in worker.managed_transfers {
            delete(
                transfer.owner_from_name,
                worker.allocator,
            )
            delete(
                transfer.owner_to_name,
                worker.allocator,
            )
        }
        mem.tracking_allocator_destroy(
            &worker.generation_allocator,
        )
        delete(worker.managed_allocations)
        delete(worker.managed_transfers)
    }
    worker^ = {}
}

worker_prepare_generation_run :: proc(worker: ^Worker) {
    if worker.allocator.procedure == nil {
        worker.allocator = context.allocator
    }
    if !worker.generation_allocator_initialized {
        mem.tracking_allocator_init(
            &worker.generation_allocator,
            worker.allocator,
            worker.allocator,
        )
        worker.managed_allocations = make(
            map[rawptr]Worker_Managed_Allocation,
            worker.allocator,
        )
        worker.generation_allocator_initialized = true
    }
    delete(worker.output)
    worker.output = ""
}

worker_run_generation_proc :: proc(
    worker: ^Worker,
    run: proc "c" (^Host_API),
    run_ns: ^i64 = nil,
) {
    worker_ensure_host_api(worker)
    if worker.trace_enabled {
        worker.trace_started_at = time.tick_now()
        worker.trace_last_at = worker.trace_started_at
    }
    worker.abort_requested = false
    worker.last_run_aborted = false
    worker.incremental_call_failed = false
    run_start := time.tick_now()
    run(&worker.host_api)
    worker.last_run_aborted = worker.abort_requested
    worker.abort_requested = false
    if run_ns != nil {
        run_ns^ =
            time.duration_nanoseconds(time.tick_since(run_start))
    }
    if worker.trace_enabled {
        elapsed_ns :=
            time.duration_nanoseconds(
                time.tick_since(worker.trace_started_at),
            )
        if worker.attached_trace_handler != nil {
            worker.attached_trace_handler(
                worker.attached_trace_ctx,
                "trace-end",
                "",
                worker.frame_depth,
                int(elapsed_ns),
                0,
            )
        } else {
            fmt.printf("%s\t%d\n", TRACE_END_MARKER, elapsed_ns)
            _ = os.flush(os.stdout)
        }
    }
    // A step request applies only to the evaluation that was paused. If that
    // evaluation returns before encountering another safe point, do not carry
    // the request into a later, unrelated generation.
    worker.step_armed = false
    worker.frame_depth = 0
    worker.trace_enabled = false
    worker.trace_remaining = 0
    worker.trace_limit_reported = false
    worker.trace_started_at = {}
    worker.trace_last_at = {}
    worker.trace_values_enabled = false
    worker.trace_values_remaining = 0
    worker.trace_values_limit_reported = false
}

worker_load_and_run :: proc(
    worker: ^Worker,
    path: string,
    load_ns: ^i64 = nil,
    run_ns: ^i64 = nil,
) -> (message: string, ok: bool) {
    worker_prepare_generation_run(worker)
    symbols := Generation_Symbols{}
    load_start := time.tick_now()
    _, loaded := dynlib.initialize_symbols(&symbols, path)
    if !loaded {
        return strings.clone("failed to load REPL generation"), false
    }
    if symbols.api_version == nil || symbols.run == nil ||
       symbols.stabilize_result == nil {
        if symbols.__handle != nil {
            _ = dynlib.unload_library(symbols.__handle)
        }
        return strings.clone("REPL generation manifest is incomplete"), false
    }
    if symbols.api_version^ != GENERATION_ABI_VERSION {
        if symbols.__handle != nil {
            _ = dynlib.unload_library(symbols.__handle)
        }
        return strings.clone("REPL generation ABI version mismatch"), false
    }

    symbols.path = strings.clone(path)
    append(&worker.generations, symbols)
    worker_ensure_host_api(worker)
    if load_ns != nil {
        load_ns^ =
            time.duration_nanoseconds(time.tick_since(load_start))
    }
    previous_result_address := worker.result_slots[0].address
    worker_run_generation_proc(worker, symbols.run, run_ns)
    if worker.result_slots[0].address != previous_result_address {
        loaded_generation := &worker.generations[len(worker.generations)-1]
        loaded_generation.result_address = worker.result_slots[0].address
    }
    return "", true
}

worker_run_loaded :: proc(
    worker: ^Worker,
    path: string,
    run_ns: ^i64 = nil,
) -> (message: string, ok: bool) {
    for &generation in worker.generations {
        if generation.path != path || generation.run == nil {
            continue
        }
        if !worker_stabilize_loaded_result(
            worker,
            &generation,
        ) {
            return strings.clone(
                "loaded REPL result cannot preserve native history",
            ), false
        }
        run := generation.run
        worker_prepare_generation_run(worker)
        worker_run_generation_proc(worker, run, run_ns)
        return "", true
    }
    return strings.clone("loaded REPL generation is unavailable"), false
}

worker_load_and_run_nested :: proc(
    worker: ^Worker,
    path: string,
) -> (message: string, ok: bool) {
    saved_frame_depth := worker.frame_depth
    saved_step_armed := worker.step_armed
    saved_step_mode := worker.step_mode
    saved_step_depth := worker.step_depth
    saved_trace_enabled := worker.trace_enabled
    saved_trace_remaining := worker.trace_remaining
    saved_trace_limit_reported := worker.trace_limit_reported
    saved_trace_started_at := worker.trace_started_at
    saved_trace_last_at := worker.trace_last_at
    saved_trace_values_enabled := worker.trace_values_enabled
    saved_trace_values_remaining := worker.trace_values_remaining
    saved_trace_values_limit_reported :=
        worker.trace_values_limit_reported

    worker.frame_depth = 0
    worker.step_armed = false
    worker.trace_enabled = false
    worker.trace_values_enabled = false
    message, ok = worker_load_and_run(worker, path)

    worker.frame_depth = saved_frame_depth
    worker.step_armed = saved_step_armed
    worker.step_mode = saved_step_mode
    worker.step_depth = saved_step_depth
    worker.trace_enabled = saved_trace_enabled
    worker.trace_remaining = saved_trace_remaining
    worker.trace_limit_reported = saved_trace_limit_reported
    worker.trace_started_at = saved_trace_started_at
    worker.trace_last_at = saved_trace_last_at
    worker.trace_values_enabled = saved_trace_values_enabled
    worker.trace_values_remaining = saved_trace_values_remaining
    worker.trace_values_limit_reported =
        saved_trace_values_limit_reported
    return
}
