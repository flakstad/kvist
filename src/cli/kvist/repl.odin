package main

import "core:bufio"
import "core:dynlib"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import kvist "../../odin/kvist"
import kvist_repl "../../odin/kvist_repl"
import repl_program "../../odin/kvist_repl_program"
import olive_reload "../../odin/olive_reload"

REPL_PROTOCOL_VERSION :: 1
REPL_WORKER_MARKER :: "KVIST_REPL_WORKER\t"
REPL_WORKER_DIRECT_INT_PREFIX :: "__direct_int__\t"
REPL_WORKER_DIRECT_SCALAR_PREFIX :: "__direct_scalar__\t"
REPL_WORKER_EXECUTION_PLAN_PREFIX :: "__execute_plan__\t"
REPL_WORKER_LOADED_NATIVE_PREFIX :: "__run_loaded_native__\t"
REPL_WORKER_ABORTED_MARKER :: "KVIST_REPL_ABORTED"
REPL_WORKER_STREAM_OUTPUT_MARKER :: "KVIST_REPL_STREAM_OUTPUT\t"
REPL_EVALUATION_ABORTED_MESSAGE :: "evaluation aborted"
REPL_WORKER_PAUSED_MARKER :: "KVIST_REPL_PAUSED\t"
REPL_WORKER_CONDITION_MARKER :: "KVIST_REPL_CONDITION\t"
REPL_WORKER_TRACE_MARKER :: "KVIST_REPL_TRACE\t"
REPL_WORKER_TRACE_LIMIT_MARKER :: "KVIST_REPL_TRACE_LIMIT\t"
REPL_WORKER_TRACE_END_MARKER :: "KVIST_REPL_TRACE_END\t"
REPL_WORKER_TRACE_VALUES_MARKER :: "KVIST_REPL_TRACE_VALUES\t"
REPL_WORKER_TRACE_VALUES_LIMIT_MARKER :: "KVIST_REPL_TRACE_VALUES_LIMIT"
REPL_WORKER_DEBUG_COLLECTIONS_MARKER :: "__collections__"
REPL_WORKER_DEBUG_PAGE_ITEM_MARKER :: "KVIST_REPL_DEBUG_PAGE_ITEM\t"
REPL_WORKER_DEBUG_COLLECTION_MARKER :: "KVIST_REPL_DEBUG_COLLECTION\t"
REPL_WORKER_DEBUG_PAGE_END_MARKER :: "KVIST_REPL_DEBUG_PAGE_END\t"
REPL_WORKER_CHECKPOINT_MARKER :: "KVIST_REPL_CHECKPOINT\t"
REPL_WORKER_CHECKPOINT_ITEM_MARKER :: "KVIST_REPL_CHECKPOINT_ITEM\t"
REPL_WORKER_CHECKPOINTS_END_MARKER :: "KVIST_REPL_CHECKPOINTS_END"
REPL_WORKER_ALLOCATION_STATS_MARKER :: "KVIST_REPL_ALLOCATION_STATS\t"
REPL_WORKER_PHYSICAL_ALLOCATION_MARKER :: "KVIST_REPL_PHYSICAL_ALLOCATION\t"
REPL_WORKER_PHYSICAL_RETAINED_OWNER_MARKER :: "KVIST_REPL_PHYSICAL_RETAINED_OWNER\t"
REPL_WORKER_PHYSICAL_RETAINED_BINDING_MARKER :: "KVIST_REPL_PHYSICAL_RETAINED_BINDING\t"
REPL_WORKER_PHYSICAL_TRANSFER_MARKER :: "KVIST_REPL_PHYSICAL_TRANSFER\t"
REPL_WORKER_PHYSICAL_ALLOCATIONS_END_MARKER :: "KVIST_REPL_PHYSICAL_ALLOCATIONS_END"
REPL_PAGE_TOTAL_MARKER :: "KVIST_REPL_PAGE_TOTAL\t"
REPL_PAGE_ITEM_MARKER :: "KVIST_REPL_PAGE_ITEM\t"
REPL_PAGE_ENTRY_MARKER :: "KVIST_REPL_PAGE_ENTRY\t"
REPL_LAYOUT_MARKER :: "KVIST_REPL_LAYOUT\t"
REPL_DEFAULT_PAGE_LIMIT :: 20
REPL_MAX_PAGE_LIMIT :: 100
REPL_DEBUG_DYNAMIC_ARRAY_LIMIT :: 64
REPL_DEFAULT_TRACE_LIMIT :: 1000
REPL_MAX_TRACE_LIMIT :: 10000
REPL_DEFAULT_TRACE_VALUE_LIMIT :: 100
REPL_MAX_TRACE_VALUE_LIMIT :: 1000
REPL_MAX_TIMEOUT_MS :: 3_600_000
REPL_NATIVE_ARTIFACT_CACHE_VERSION :: 1
REPL_NATIVE_ARTIFACT_CACHE_LIMIT :: 128
REPL_RESTART_CONTINUE :: u32(1 << 0)
REPL_RESTART_USE_VALUE :: u32(1 << 1)
REPL_RESTART_RETRY :: u32(1 << 2)
REPL_RESTART_SKIP :: u32(1 << 3)
REPL_RESTART_ABORT_OPERATION :: u32(1 << 4)

Repl_Execution_Mode :: enum {
    Auto,
    Resident,
    Native_Adapter,
    Native_Reuse,
    Native,
}

repl_execution_mode_name :: proc(mode: Repl_Execution_Mode) -> string {
    switch mode {
    case .Auto:           return "auto"
    case .Resident:       return "resident"
    case .Native_Adapter: return "native-adapter"
    case .Native_Reuse:   return "native-reuse"
    case .Native:         return "native"
    }
    return "auto"
}

repl_execution_mode_parse :: proc(text: string) -> (Repl_Execution_Mode, bool) {
    switch text {
    case "auto":           return .Auto, true
    case "resident":       return .Resident, true
    case "native-adapter": return .Native_Adapter, true
    case "native-reuse":   return .Native_Reuse, true
    case "native":         return .Native, true
    case:                   return .Auto, false
    }
}

repl_execution_mode_allows_plan :: proc(mode: Repl_Execution_Mode) -> bool {
    return mode == .Auto || mode == .Resident
}

repl_execution_mode_allows_adapter :: proc(mode: Repl_Execution_Mode) -> bool {
    return repl_execution_mode_allows_plan(mode) || mode == .Native_Adapter
}

repl_execution_mode_allows_loaded_native :: proc(
    mode: Repl_Execution_Mode,
) -> bool {
    return mode == .Auto || mode == .Native_Adapter ||
           mode == .Native_Reuse
}

REPL_DEBUG_CAPABILITIES: [72]string = {
    "compiled-abort-operation-restarts",
    "compiled-retry-skip-restarts",
    "native-attach",
    "nested-break-eval",
    "session-state-checkpoints",
    "typed-conditions",
    "debug-symbols",
    "generation-loaded-events",
    "evaluation-phase-timings",
    "execution-modes",
    "loaded-native-reuse",
    "native-artifact-cache",
    "frontend-generation-cache",
    "context-expansion-cache",
    "thin-scalar-generations",
    "reachable-native-generations",
    "resident-direct-int-calls",
    "resident-direct-scalar-calls",
    "typed-resident-execution-plans",
    "deferred-debug-value-capture",
    "generated-source-maps",
    "kvist-breakpoint-locations",
    "instrumented-conditions",
    "instrumented-debug-abort",
    "instrumented-pause-before",
    "instrumented-step-into",
    "instrumented-step-out",
    "instrumented-step-over",
    "instrumented-trace",
    "instrumented-trace-summary",
    "instrumented-trace-timing",
    "instrumented-trace-values",
    "paused-direct-struct-fields",
    "paused-dynamic-array-paths",
    "paused-dynamic-array-pages",
    "paused-fixed-array-paths",
    "paused-frame-eval",
    "paused-local-snapshots",
    "paused-map-pages",
    "paused-map-paths",
    "paused-nested-collection-pages",
    "paused-nested-collection-roots",
    "paused-nested-struct-fields",
    "paused-runtime-nested-collection-pages",
    "paused-runtime-page-discovery",
    "typed-frame-descriptors",
    "typed-use-value-restarts",
    "versioned-definition-frames",
    "worker-replacement-events",
    "session-completion",
    "session-lookup",
    "session-documentation",
    "session-xref",
    "lifecycle-metadata",
    "nested-retained-views",
    "paused-force-interrupt",
    "evaluation-deadlines",
    "native-crash-events",
    "separate-worker-streams",
    "unretained-lifecycle-diagnostics",
    "native-layout-metadata",
    "inspection-definition-versions",
    "cached-inspection-snapshots",
    "logical-allocation-inventory",
    "ownership-lifecycle-history",
    "runtime-checkpoint-allocation-stats",
    "generation-managed-allocation-stats",
    "physical-allocation-inventory",
    "physical-result-ownership-transfers",
    "shared-data-physical-ownership",
    "map-result-physical-ownership",
    "binding-physical-ownership",
}

Repl_Optional_Int :: union {
    int,
}

Repl_Optional_Bool :: union {
    bool,
}

Repl_Request :: struct {
    id:         string,
    op:         string,
    name:       string,
    version:    Repl_Optional_Int,
    source:     string,
    handle:     string,
    path:       [dynamic]string,
    index:      Repl_Optional_Int,
    key_source: string,
    offset:     Repl_Optional_Int,
    limit:      Repl_Optional_Int,
    source_path: string,
    line:        Repl_Optional_Int,
    column:      Repl_Optional_Int,
    pause_id:     string,
    pause_before: bool,
    no_print:     bool,
    native_debug_symbols: bool,
    trace:             bool,
    trace_limit:       Repl_Optional_Int,
    trace_values:      bool,
    trace_value_limit: Repl_Optional_Int,
    defer_debug_values: bool,
    timeout_ms:        Repl_Optional_Int,
    abi:               string,
}

Repl_Restart :: struct {
    name:           string,
    label:          string,
    requires_value: bool `json:",omitempty"`,
    value_type:     string `json:",omitempty"`,
}

Repl_Symbol :: struct {
    kind:      string,
    name:      string,
    line:      int,
    column:    int,
    detail:    string `json:",omitempty"`,
    signature: string `json:",omitempty"`,
    doc:       string `json:",omitempty"`,
    file:      string `json:",omitempty"`,
}

Repl_Diagnostic :: struct {
    severity:    string,
    code:        string `json:",omitempty"`,
    confidence:  string `json:",omitempty"`,
    phase:       string,
    message:     string,
    source_path: string `json:",omitempty"`,
    line:        int,
    column:      int,
    end_line:    int,
    end_column:  int,
}

Repl_Lifecycle :: struct {
    ownership: string `json:",omitempty"`,
    storage:    string `json:",omitempty"`,
    clone:      string `json:",omitempty"`,
    destroy:    string `json:",omitempty"`,
    checkpoint: string `json:",omitempty"`,
    render:     string `json:",omitempty"`,
}

Repl_Optional_Lifecycle :: union {
    Repl_Lifecycle,
}

Repl_Timing :: struct {
    phase:      string,
    elapsed_ns: i64,
}

Repl_Eval_Timings :: struct {
    profile:              kvist.Compile_Profile,
    preparation_ns:       i64,
    frontend_ns:          i64,
    source_generation_ns: i64,
    odin_build_ns:        i64,
    worker_run_ns:        i64,
    worker_load_ns:       i64,
    native_run_ns:        i64,
    commit_ns:            i64,
    total_ns:             i64,
    generated_bytes:      int,
    native_cache_hit:     bool,
    frontend_cache_hit:   bool,
    execution_path:       string,
}

repl_eval_timing_entries :: proc(
    timings: ^Repl_Eval_Timings,
) -> [20]Repl_Timing {
    profile := &timings.profile
    attributed_frontend_ns :=
        profile.load_and_resolve_ns +
        profile.macro_expansion_ns +
        profile.post_expand_resolution_ns +
        profile.ast_parse_ns +
        profile.lowering_ns +
        profile.analysis_ns +
        profile.emission_ns +
        profile.source_map_ns +
        profile.analysis_and_emission_ns
    return {
        {"controller-preparation", timings.preparation_ns},
        {"frontend-total", timings.frontend_ns},
        {"frontend-load-resolve", profile.load_and_resolve_ns},
        {"frontend-macro-expansion", profile.macro_expansion_ns},
        {"frontend-post-expand-resolution", profile.post_expand_resolution_ns},
        {"frontend-parse", profile.ast_parse_ns},
        {"frontend-lowering", profile.lowering_ns},
        {"frontend-analysis", profile.analysis_ns},
        {"frontend-emission", profile.emission_ns},
        {"frontend-source-map", profile.source_map_ns},
        {"frontend-legacy-analysis-emission", profile.analysis_and_emission_ns},
        {
            "frontend-unattributed",
            max(timings.frontend_ns-attributed_frontend_ns, 0),
        },
        {"generated-source", timings.source_generation_ns},
        {"odin-build", timings.odin_build_ns},
        {"worker-roundtrip", timings.worker_run_ns},
        {"worker-load", timings.worker_load_ns},
        {"native-run", timings.native_run_ns},
        {
            "worker-unattributed",
            max(
                timings.worker_run_ns -
                    timings.worker_load_ns -
                    timings.native_run_ns,
                0,
            ),
        },
        {"session-commit", timings.commit_ns},
        {"controller-total", timings.total_ns},
    }
}

Repl_Event :: struct {
    protocol_version: int,
    id:               string,
    kind:             string,
    success:          bool,
    generation:       int,
    message:          string `json:",omitempty"`,
    stream:           string `json:",omitempty"`,
    text:             string `json:",omitempty"`,
    ty:               string `json:"type,omitempty"`,
    abi:              string `json:",omitempty"`,
    handle:           string `json:",omitempty"`,
    path:             []string `json:",omitempty"`,
    index:            Repl_Optional_Int `json:",omitempty"`,
    key_source:       string `json:",omitempty"`,
    shape:            string `json:",omitempty"`,
    element_type:     string `json:",omitempty"`,
    key_type:         string `json:",omitempty"`,
    value_type:       string `json:",omitempty"`,
    length:           ^int `json:",omitempty"`,
    members:          []Repl_Inspection_Member `json:",omitempty"`,
    offset:           Repl_Optional_Int `json:",omitempty"`,
    limit:            Repl_Optional_Int `json:",omitempty"`,
    total:            Repl_Optional_Int `json:",omitempty"`,
    entries:          []Repl_Inspection_Entry `json:",omitempty"`,
    bindings:         []Repl_Session_Binding `json:",omitempty"`,
    versions:         []Repl_Binding_Version `json:",omitempty"`,
    results:          []Repl_Result `json:",omitempty"`,
    generations:      []Repl_Loaded_Generation `json:",omitempty"`,
    worker_pid:       Repl_Optional_Int `json:",omitempty"`,
    worker_epoch:     Repl_Optional_Int `json:",omitempty"`,
    capabilities:     []string `json:",omitempty"`,
    breakpoints:      []Repl_Breakpoint_Location `json:",omitempty"`,
    pause_id:         string `json:",omitempty"`,
    condition_type:   string `json:",omitempty"`,
    condition_data:   string `json:",omitempty"`,
    restarts:         []Repl_Restart `json:",omitempty"`,
    restart:          string `json:",omitempty"`,
    collection_path:  string `json:",omitempty"`,
    collections:      []Repl_Debug_Collection `json:",omitempty"`,
    source_path:      string `json:",omitempty"`,
    line:             Repl_Optional_Int `json:",omitempty"`,
    column:           Repl_Optional_Int `json:",omitempty"`,
    end_line:         Repl_Optional_Int `json:",omitempty"`,
    end_column:       Repl_Optional_Int `json:",omitempty"`,
    name:             string `json:",omitempty"`,
    definition_kind:  string `json:",omitempty"`,
    version:          Repl_Optional_Int `json:",omitempty"`,
    definition_generation: Repl_Optional_Int `json:",omitempty"`,
    frames:           []Repl_Debug_Frame `json:",omitempty"`,
    trace_id:              string `json:",omitempty"`,
    depth:                 Repl_Optional_Int `json:",omitempty"`,
    elapsed_ns:            Repl_Optional_Int `json:",omitempty"`,
    delta_ns:              Repl_Optional_Int `json:",omitempty"`,
    trace_points:          Repl_Optional_Int `json:",omitempty"`,
    trace_total_ns:        Repl_Optional_Int `json:",omitempty"`,
    trace_unattributed_ns: Repl_Optional_Int `json:",omitempty"`,
    hotspots:              []Repl_Trace_Hotspot `json:",omitempty"`,
    trace_values:          []Repl_Trace_Value `json:",omitempty"`,
    checkpoint:            string `json:",omitempty"`,
    checkpoint_bindings:   Repl_Optional_Int `json:",omitempty"`,
    checkpoints:           []Repl_Checkpoint `json:",omitempty"`,
    attached:              bool `json:",omitempty"`,
    attached_capabilities: []Repl_Attached_Capability `json:",omitempty"`,
    reload_requested:      bool `json:",omitempty"`,
    application_generation: Repl_Optional_Int `json:",omitempty"`,
    attached_generation:    Repl_Optional_Int `json:",omitempty"`,
    symbols:                 []Repl_Symbol `json:",omitempty"`,
    diagnostics:             []Repl_Diagnostic `json:",omitempty"`,
    timeout_ms:              Repl_Optional_Int `json:",omitempty"`,
    failure_kind:            string `json:",omitempty"`,
    exit_code:               Repl_Optional_Int `json:",omitempty"`,
    lifecycle:               Repl_Optional_Lifecycle `json:",omitempty"`,
    owner_id:                string `json:",omitempty"`,
    allocation_id:           string `json:",omitempty"`,
    retained_owner_chain:    []string `json:",omitempty"`,
    size:                     Repl_Optional_Int `json:",omitempty"`,
    alignment:                Repl_Optional_Int `json:",omitempty"`,
    allocations:              []Repl_Allocation `json:",omitempty"`,
    allocation_count:        Repl_Optional_Int `json:",omitempty"`,
    known_allocation_bytes:   Repl_Optional_Int `json:",omitempty"`,
    known_allocation_count:   Repl_Optional_Int `json:",omitempty"`,
    ownership_events:         []Repl_Ownership_Event `json:",omitempty"`,
    ownership_event_count:    Repl_Optional_Int `json:",omitempty"`,
    runtime_live_allocations:  Repl_Optional_Int `json:",omitempty"`,
    runtime_live_bytes:        Repl_Optional_Int `json:",omitempty"`,
    runtime_total_allocations: Repl_Optional_Int `json:",omitempty"`,
    runtime_total_allocated_bytes: Repl_Optional_Int `json:",omitempty"`,
    runtime_total_frees:       Repl_Optional_Int `json:",omitempty"`,
    runtime_total_freed_bytes: Repl_Optional_Int `json:",omitempty"`,
    managed_live_allocations:  Repl_Optional_Int `json:",omitempty"`,
    managed_live_bytes:        Repl_Optional_Int `json:",omitempty"`,
    managed_peak_bytes:        Repl_Optional_Int `json:",omitempty"`,
    managed_total_allocations: Repl_Optional_Int `json:",omitempty"`,
    managed_total_allocated_bytes: Repl_Optional_Int `json:",omitempty"`,
    managed_total_frees:       Repl_Optional_Int `json:",omitempty"`,
    managed_total_freed_bytes: Repl_Optional_Int `json:",omitempty"`,
    physical_allocations:      []Repl_Physical_Allocation `json:",omitempty"`,
    physical_allocation_count: Repl_Optional_Int `json:",omitempty"`,
    physical_transfers:        []Repl_Physical_Transfer `json:",omitempty"`,
    physical_transfer_count:   Repl_Optional_Int `json:",omitempty"`,
    timings:                    []Repl_Timing `json:",omitempty"`,
    generated_bytes:            Repl_Optional_Int `json:",omitempty"`,
    native_cache_hit:            bool `json:",omitempty"`,
    frontend_cache_hit:          bool `json:",omitempty"`,
    execution_mode:              string `json:",omitempty"`,
    execution_path:              string `json:",omitempty"`,
}

Repl_Attached_Capability :: struct {
    name:      string,
    signature: string,
}

Repl_Checkpoint :: struct {
    name:     string,
    bindings: int,
}

Repl_Trace_Value :: struct {
    name:      string,
    ty:        string `json:"type"`,
    mutable:   bool,
    ownership: string,
    value:     string,
}

Repl_Trace_Hotspot :: struct {
    source_path: string `json:",omitempty"`,
    line:        Repl_Optional_Int `json:",omitempty"`,
    column:      Repl_Optional_Int `json:",omitempty"`,
    trace_id:    string,
    hits:        int,
    total_ns:    int,
    max_ns:      int,
}

Repl_Trace_Sample :: struct {
    source_path: string,
    line:        int,
    column:      int,
    trace_id:    string,
    elapsed_ns:  int,
}

Repl_Inspection_Member :: struct {
    name: string `json:",omitempty"`,
    ty:   string `json:"type,omitempty"`,
}

Repl_Inspection_Entry :: struct {
    index: Repl_Optional_Int `json:",omitempty"`,
    key:   string `json:",omitempty"`,
    value: string,
}

Repl_Inspection_Schema :: struct {
    shape:        string,
    element_type: string,
    key_type:     string,
    value_type:   string,
    length:       int,
    has_length:   bool,
    members:      [dynamic]Repl_Inspection_Member,
}

Repl_Worker_Process :: struct {
    process: os.Process,
    input:   ^os.File,
    output:  ^os.File,
    reader:  bufio.Reader,
    alive:   bool,
    stderr_file:      ^os.File,
    stderr_dir:       string,
    stderr_path:      string,
    stderr_offset:    i64,
    captured_stderr:  string,
    termination_kind: string,
    exit_code:        int,
    has_exit_code:    bool,
}

Repl_Deadline_Watchdog :: struct {
    mutex:      sync.Atomic_Mutex,
    condition:  sync.Atomic_Cond,
    process:    os.Process,
    timeout_ms: int,
    done:       bool,
    timed_out:  bool,
}

repl_deadline_watchdog_run :: proc(data: rawptr) {
    watchdog := cast(^Repl_Deadline_Watchdog)data
    sync.atomic_mutex_lock(&watchdog.mutex)
    woke := sync.atomic_cond_wait_with_timeout(
        &watchdog.condition,
        &watchdog.mutex,
        time.Duration(watchdog.timeout_ms)*time.Millisecond,
    )
    should_terminate := !woke && !watchdog.done
    if should_terminate {
        watchdog.timed_out = true
    }
    sync.atomic_mutex_unlock(&watchdog.mutex)
    if should_terminate {
        terminate_err := os.process_terminate(watchdog.process)
        if terminate_err != nil {
            _ = os.process_kill(watchdog.process)
        }
    }
}

repl_deadline_watchdog_finish :: proc(
    watchdog: ^Repl_Deadline_Watchdog,
    watchdog_thread: ^thread.Thread,
) {
    if watchdog_thread == nil {
        return
    }
    sync.atomic_mutex_lock(&watchdog.mutex)
    watchdog.done = true
    sync.atomic_cond_signal(&watchdog.condition)
    sync.atomic_mutex_unlock(&watchdog.mutex)
    thread.destroy(watchdog_thread)
}

repl_deadline_watchdog_timed_out :: proc(
    watchdog: ^Repl_Deadline_Watchdog,
) -> bool {
    sync.atomic_mutex_lock(&watchdog.mutex)
    timed_out := watchdog.timed_out
    sync.atomic_mutex_unlock(&watchdog.mutex)
    return timed_out
}

Repl_Binding_Version :: struct {
    version:      int,
    generation:   int,
    kind:         string,
    abi:          string `json:",omitempty"`,
    dependencies: [dynamic]string `json:",omitempty"`,
    source_path:         string `json:",omitempty"`,
    source_start_line:   int    `json:",omitempty"`,
    source_start_column: int    `json:",omitempty"`,
    source_end_line:     int    `json:",omitempty"`,
    source_end_column:   int    `json:",omitempty"`,
}

Repl_Session_Binding :: struct {
    name:         string,
    kind:         string,
    version:      int,
    generation:   int,
    abi:          string `json:",omitempty"`,
    dependencies: [dynamic]string `json:",omitempty"`,
    stale:        bool `json:",omitempty"`,
    ty:            string `json:"type,omitempty"`,
    lifecycle:     Repl_Optional_Lifecycle `json:",omitempty"`,
    owner_id:      string `json:",omitempty"`,
    allocation_id: string `json:",omitempty"`,
    source_path:         string `json:"-"`,
    source_start_line:   int    `json:"-"`,
    source_start_column: int    `json:"-"`,
    source_end_line:     int    `json:"-"`,
    source_end_column:   int    `json:"-"`,
    source:       string `json:"-"`,
    identity:     string `json:"-"`,
    direct_scalar_invoke: bool `json:"-"`,
    dependency_identities: [dynamic]string `json:"-"`,
    versions:     [dynamic]Repl_Binding_Version `json:"-"`,
}

Repl_Result :: struct {
    slot:       int,
    name:       string,
    ty:         string `json:"type"`,
    abi:        string,
    generation: int,
    lifecycle:  Repl_Lifecycle,
    owner_id:   string,
    allocation_id: string,
}

Repl_Allocation :: struct {
    allocation_id: string,
    owner_id:      string,
    kind:          string,
    name:          string `json:",omitempty"`,
    ty:            string `json:"type,omitempty"`,
    abi:           string `json:",omitempty"`,
    generation:    int,
    version:       Repl_Optional_Int `json:",omitempty"`,
    lifecycle:     Repl_Lifecycle,
    retained_owner_chain: [1]string,
    size:          Repl_Optional_Int `json:",omitempty"`,
    alignment:     Repl_Optional_Int `json:",omitempty"`,
}

Repl_Physical_Allocation :: struct {
    allocation_id: string,
    owner_id:      string,
    kind:          string,
    size:          int,
    alignment:     int,
    generation:    int,
    retained_owner_chain: [dynamic]string,
}

Repl_Physical_Transfer :: struct {
    sequence:      int,
    allocation_id: string,
    owner_from:    string,
    owner_to:      string,
    generation:    int,
    action:        string,
    reason:        string,
}

Repl_Ownership_Event :: struct {
    sequence:      int,
    allocation_id: string,
    action:        string,
    generation:    int,
    name:          string `json:",omitempty"`,
    ty:            string `json:"type,omitempty"`,
    owner_from:    string `json:",omitempty"`,
    owner_to:      string `json:",omitempty"`,
    reason:        string,
}

Repl_Loaded_Generation :: struct {
    generation:   int,
    source_path:  string,
    map_path:     string,
    library_path: string,
    debug_symbols: bool,
    breakpoint_locations: [dynamic]Repl_Breakpoint_Location `json:"-"`,
    pause_points:         [dynamic]Repl_Debug_Frame `json:"-"`,
}

Repl_Breakpoint_Location :: struct {
    generation:             int,
    source_path:            string,
    source_start_line:      int,
    source_start_column:    int,
    source_end_line:        int,
    source_end_column:      int,
    generated_path:         string,
    generated_start_line:   int,
    generated_start_column: int `json:",omitempty"`,
    generated_end_line:     int,
    generated_end_column:   int `json:",omitempty"`,
}

Repl_Debug_Path :: struct {
    path:  string,
    ty:    string `json:"type"`,
    value: string,
}

Repl_Debug_Local :: struct {
    name:      string,
    ty:        string `json:"type"`,
    mutable:   bool,
    ownership: string,
    value:     string,
    paths:     [dynamic]Repl_Debug_Path `json:",omitempty"`,
    element_paths: [dynamic]Repl_Debug_Path `json:"-"`,
    element_type: string `json:",omitempty"`,
    map_value_paths: [dynamic]Repl_Debug_Path `json:"-"`,
    key_type:   string `json:",omitempty"`,
    value_type: string `json:",omitempty"`,
    capture_limit: Repl_Optional_Int `json:",omitempty"`,
    total:        Repl_Optional_Int `json:",omitempty"`,
    truncated:    Repl_Optional_Bool `json:",omitempty"`,
    lifecycle: Repl_Lifecycle,
}

Repl_Debug_Collection :: struct {
    path:          string,
    shape:         string,
    element_type:  string `json:",omitempty"`,
    key_type:      string `json:",omitempty"`,
    value_type:    string `json:",omitempty"`,
    descriptor:    int `json:"-"`,
}

Repl_Debug_Frame :: struct {
    frame_id:    string,
    pause_id:    string,
    generation:  int,
    definition_name:    string `json:",omitempty"`,
    definition_version: Repl_Optional_Int `json:",omitempty"`,
    source_path: string,
    line:        int,
    column:      int,
    phase:       string,
    locals:      [dynamic]Repl_Debug_Local,
    collections: [dynamic]Repl_Debug_Collection `json:",omitempty"`,
}

Repl_Session :: struct {
    definitions: [dynamic]string,
    bindings:    [dynamic]Repl_Session_Binding,
    results:     [3]Repl_Result,
    result_count: int,
    inspections: [dynamic]Repl_Inspection,
    next_inspection: int,
    generations: [dynamic]Repl_Loaded_Generation,
    ownership_events: [dynamic]Repl_Ownership_Event,
    next_ownership_event: int,
    compiled_generations: [dynamic]Repl_Compiled_Generation,
    resident_scalar_invokes: [dynamic]kvist.Repl_Scalar_Invoke_Metadata,
}

Repl_Compiled_Generation :: struct {
    source_hash:     u64,
    request_hash:    u64,
    generation:      int,
    library_path:    string,
    emitted_source:  string,
    warning_text:    string,
    diagnostics:     [dynamic]Repl_Diagnostic,
    dependency_files: [dynamic]Dependency_File_Fingerprint,
    dependency_directories: [dynamic]Dependency_Directory_Fingerprint,
    resident_recent_result_mask: u8,
    resident_recent_result_types: [3]string,
    generated_bytes: int,
}

Repl_Native_Artifact_Metadata :: struct {
    version:      int,
    content_hash: u64,
    size:         i64,
}

repl_native_toolchain_mutex: sync.Mutex
repl_native_toolchain_initialized: bool
repl_native_toolchain_hash: u64
repl_native_toolchain_ok: bool

Repl_Inspection :: struct {
    handle:     string,
    slot:       string,
    ty:         string,
    abi:        string,
    generation: int,
    snapshot_output: string,
    size:       int,
    alignment:  int,
    owner_id:   string,
}

repl_inspection_map_close :: proc(ty: string) -> int {
    if !strings.has_prefix(ty, "map[") {
        return -1
    }
    depth := 0
    for i := len("map["); i < len(ty); i += 1 {
        if ty[i] == '[' {
            depth += 1
        } else if ty[i] == ']' {
            if depth == 0 {
                return i
            }
            depth -= 1
        }
    }
    return -1
}

repl_inspection_layout :: proc(abi, ty: string) -> (
    kind,
    body: string,
    ok: bool,
) {
    needle := fmt.tprintf("|layout:%s=", ty)
    offset := strings.index(abi, needle)
    if offset < 0 {
        return "", "", false
    }
    layout := abi[offset+len(needle):]
    candidates := [3]string{"struct{", "enum{", "union{"}
    for candidate in candidates {
        if !strings.has_prefix(layout, candidate) {
            continue
        }
        depth := 0
        for i := len(candidate); i < len(layout); i += 1 {
            if layout[i] == '{' {
                depth += 1
            } else if layout[i] == '}' {
                if depth == 0 {
                    return candidate[:len(candidate)-1],
                           layout[len(candidate):i],
                           true
                }
                depth -= 1
            }
        }
        return "", "", false
    }
    if strings.has_prefix(layout, "alias:") {
        end := strings.index(layout, "|layout:")
        if end < 0 {
            end = len(layout)
        }
        return "alias", layout[len("alias:"):end], true
    }
    return "", "", false
}

repl_inspection_member_separator :: proc(text: string) -> int {
    round_depth, square_depth, brace_depth := 0, 0, 0
    for ch, i in text {
        switch ch {
        case '(': round_depth += 1
        case ')': round_depth -= 1
        case '[': square_depth += 1
        case ']': square_depth -= 1
        case '{': brace_depth += 1
        case '}': brace_depth -= 1
        case ';':
            if round_depth == 0 && square_depth == 0 && brace_depth == 0 {
                return i
            }
        case:
        }
    }
    return -1
}

repl_type_lifecycle :: proc(
    ty,
    abi: string,
    ownership_hint := "",
) -> Repl_Lifecycle {
    trimmed := strings.trim_space(ty)
    if trimmed == "" {
        return {}
    }
    if strings.has_prefix(trimmed, "^") ||
       trimmed == "rawptr" ||
       trimmed == "cstring" {
        return Repl_Lifecycle{
            ownership = "borrowed",
            storage = "foreign",
            clone = "unsupported",
            destroy = "none",
            checkpoint = "unsupported",
            render = "address",
        }
    }
    if ownership_hint != "" {
        ownership := "value"
        storage := "frame"
        clone := "copy"
        checkpoint := "copy"
        if ownership_hint == "owned" {
            ownership = "owned"
            clone = "snapshot"
            checkpoint = "snapshot"
        } else if ownership_hint == "borrowed" {
            ownership = "borrowed"
            clone = "promote"
            checkpoint = "snapshot"
        }
        return Repl_Lifecycle{
            ownership = ownership,
            storage = storage,
            clone = clone,
            destroy = "frame-exit",
            checkpoint = checkpoint,
            render = "native",
        }
    }
    if strings.has_prefix(trimmed, "[]") {
        return Repl_Lifecycle{
            ownership = "retained-view",
            storage = "worker-backed",
            clone = "promote",
            destroy = "worker-exit",
            checkpoint = "snapshot",
            render = "native",
        }
    }
    retained :=
        trimmed == "string" ||
        trimmed == "Data" ||
        strings.has_prefix(trimmed, "[dynamic]") ||
        strings.has_prefix(trimmed, "map[") ||
        strings.contains(trimmed, "[]") ||
        strings.contains(trimmed, "[dynamic]") ||
        strings.contains(trimmed, "map[") ||
        strings.contains(abi, ":string;") ||
        strings.contains(abi, ":Data;") ||
        strings.contains(abi, ":[]") ||
        strings.contains(abi, ":[dynamic]") ||
        strings.contains(abi, ":map[")
    if retained {
        clone := "snapshot"
        if trimmed == "Data" {
            clone = "retain"
        }
        return Repl_Lifecycle{
            ownership = "owned",
            storage = "worker",
            clone = clone,
            destroy = "deferred",
            checkpoint = "snapshot",
            render = "native",
        }
    }
    return Repl_Lifecycle{
        ownership = "value",
        storage = "inline",
        clone = "copy",
        destroy = "none",
        checkpoint = "copy",
        render = "native",
    }
}

repl_inspection_append_members :: proc(
    members: ^[dynamic]Repl_Inspection_Member,
    shape,
    body: string,
) {
    rest := body
    for rest != "" {
        separator := repl_inspection_member_separator(rest)
        if separator < 0 {
            break
        }
        item := rest[:separator]
        rest = rest[separator+1:]
        if item == "" {
            continue
        }
        if shape == "struct" {
            colon := strings.index(item, ":")
            if colon > 0 && colon+1 < len(item) {
                append(members, Repl_Inspection_Member{
                    name = item[:colon],
                    ty = item[colon+1:],
                })
            }
        } else if shape == "enum" {
            append(members, Repl_Inspection_Member{name = item})
        } else {
            append(members, Repl_Inspection_Member{ty = item})
        }
    }
}

repl_inspection_schema :: proc(ty, abi: string) -> Repl_Inspection_Schema {
    schema := Repl_Inspection_Schema{}
    if layout_kind, body, has_layout := repl_inspection_layout(abi, ty); has_layout {
        schema.shape = layout_kind
        if layout_kind == "alias" {
            schema.element_type = body
        } else {
            repl_inspection_append_members(&schema.members, layout_kind, body)
        }
        return schema
    }
    if strings.has_prefix(ty, "map[") {
        close := repl_inspection_map_close(ty)
        if close > len("map[") && close+1 < len(ty) {
            schema.shape = "map"
            schema.key_type = ty[len("map["):close]
            schema.value_type = ty[close+1:]
            return schema
        }
    }
    if strings.has_prefix(ty, "[dynamic]") {
        schema.shape = "dynamic-array"
        schema.element_type = ty[len("[dynamic]"):]
    } else if strings.has_prefix(ty, "[]") {
        schema.shape = "slice"
        schema.element_type = ty[len("[]"):]
    } else if strings.has_prefix(ty, "[") {
        close := strings.index(ty, "]")
        if close > 1 && close+1 < len(ty) {
            parsed_length, parsed := strconv.parse_int(ty[1:close])
            schema.shape = "fixed-array"
            if parsed {
                schema.length = parsed_length
                schema.has_length = true
            }
            schema.element_type = ty[close+1:]
        }
    } else if strings.has_prefix(ty, "^") {
        schema.shape = "pointer"
        schema.element_type = ty[1:]
    } else if ty == "Data" {
        schema.shape = "data"
    } else if ty == "string" || ty == "cstring" {
        schema.shape = "string"
    } else if strings.has_prefix(ty, "proc(") {
        schema.shape = "procedure"
    } else {
        schema.shape = "scalar"
    }
    return schema
}

repl_inspection_path_segment_ok :: proc(segment: string) -> bool {
    if segment == "" {
        return false
    }
    for ch, i in segment {
        if (ch >= 'a' && ch <= 'z') ||
           (ch >= 'A' && ch <= 'Z') ||
           ch == '_' ||
           (i > 0 && ch >= '0' && ch <= '9') {
            continue
        }
        return false
    }
    return true
}

repl_inspection_child_source :: proc(
    slot: string,
    path: []string,
    index: int,
    has_index: bool,
    key_source: string,
) -> (source: string, ok: bool) {
    selector_count := 0
    if len(path) > 0 {
        selector_count += 1
    }
    if has_index {
        selector_count += 1
    }
    if key_source != "" {
        selector_count += 1
    }
    if slot == "" || selector_count != 1 {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, slot)
    if len(path) > 0 {
        for segment in path {
            if !repl_inspection_path_segment_ok(segment) {
                return "", false
            }
            strings.write_byte(&builder, '.')
            strings.write_string(&builder, segment)
        }
    } else if has_index {
        if index < 0 {
            return "", false
        }
        fmt.sbprintf(&builder, "[%d]", index)
    } else {
        strings.write_byte(&builder, '[')
        strings.write_string(&builder, key_source)
        strings.write_byte(&builder, ']')
    }
    return strings.clone(strings.to_string(builder)), true
}

repl_parse_inspection_layout :: proc(output: string) -> (
    payload: string,
    size,
    alignment: int,
    ok: bool,
) {
    if !strings.has_prefix(output, REPL_LAYOUT_MARKER) {
        return output, 0, 0, false
    }
    line_end := strings.index(output, "\n")
    if line_end < 0 {
        return output, 0, 0, false
    }
    fields :=
        strings.split(
            output[len(REPL_LAYOUT_MARKER):line_end],
            "\t",
            context.temp_allocator,
        )
    if len(fields) != 2 {
        return output, 0, 0, false
    }
    parsed_size, size_ok := strconv.parse_int(fields[0])
    parsed_alignment, alignment_ok := strconv.parse_int(fields[1])
    if !size_ok ||
       !alignment_ok ||
       parsed_size < 0 ||
       parsed_alignment <= 0 {
        return output, 0, 0, false
    }
    return output[line_end+1:], parsed_size, parsed_alignment, true
}

repl_parse_inspection_page :: proc(output: string) -> (
    entries: [dynamic]Repl_Inspection_Entry,
    total: int,
    ok: bool,
) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    found_total := false
    for line in lines {
        if strings.has_prefix(line, REPL_PAGE_TOTAL_MARKER) {
            parsed_total, parsed :=
                strconv.parse_int(line[len(REPL_PAGE_TOTAL_MARKER):])
            if !parsed || parsed_total < 0 {
                return entries, 0, false
            }
            total = parsed_total
            found_total = true
            continue
        }
        if strings.has_prefix(line, REPL_PAGE_ITEM_MARKER) {
            body := line[len(REPL_PAGE_ITEM_MARKER):]
            separator := strings.index(body, "\t")
            if separator <= 0 {
                return entries, 0, false
            }
            parsed_index, parsed := strconv.parse_int(body[:separator])
            if !parsed || parsed_index < 0 {
                return entries, 0, false
            }
            append(&entries, Repl_Inspection_Entry{
                index = Repl_Optional_Int(parsed_index),
                value = strings.clone(body[separator+1:]),
            })
            continue
        }
        if strings.has_prefix(line, REPL_PAGE_ENTRY_MARKER) {
            body := line[len(REPL_PAGE_ENTRY_MARKER):]
            separator := strings.index(body, "\t")
            if separator <= 0 {
                return entries, 0, false
            }
            append(&entries, Repl_Inspection_Entry{
                key = strings.clone(body[:separator]),
                value = strings.clone(body[separator+1:]),
            })
            continue
        }
        if strings.trim_space(line) != "" {
            return entries, 0, false
        }
    }
    return entries, total, found_total
}

repl_inspection_entries_delete :: proc(entries: []Repl_Inspection_Entry) {
    for entry in entries {
        if entry.key != "" {
            delete(entry.key)
        }
        delete(entry.value)
    }
    delete(entries)
}

repl_result_delete :: proc(result: ^Repl_Result) {
    delete(result.name)
    delete(result.ty)
    delete(result.abi)
    delete(result.owner_id)
    delete(result.allocation_id)
    result^ = {}
}

repl_session_clear_results :: proc(session: ^Repl_Session) {
    for &result in session.results {
        repl_result_delete(&result)
    }
    session.result_count = 0
}

repl_inspection_delete :: proc(inspection: ^Repl_Inspection) {
    delete(inspection.handle)
    delete(inspection.slot)
    delete(inspection.ty)
    delete(inspection.abi)
    delete(inspection.snapshot_output)
    delete(inspection.owner_id)
    inspection^ = {}
}

repl_ownership_event_delete :: proc(event: ^Repl_Ownership_Event) {
    delete(event.allocation_id)
    delete(event.action)
    delete(event.name)
    delete(event.ty)
    delete(event.owner_from)
    delete(event.owner_to)
    delete(event.reason)
    event^ = {}
}

repl_session_record_ownership_event :: proc(
    session: ^Repl_Session,
    allocation_id,
    action: string,
    generation: int,
    name := "",
    ty := "",
    owner_from := "",
    owner_to := "",
    reason := "",
) {
    if allocation_id == "" {
        return
    }
    session.next_ownership_event += 1
    append(&session.ownership_events, Repl_Ownership_Event{
        sequence = session.next_ownership_event,
        allocation_id = strings.clone(allocation_id),
        action = strings.clone(action),
        generation = generation,
        name = strings.clone(name),
        ty = strings.clone(ty),
        owner_from = strings.clone(owner_from),
        owner_to = strings.clone(owner_to),
        reason = strings.clone(reason),
    })
}

repl_session_cache_inspection :: proc(
    session: ^Repl_Session,
    handle,
    output: string,
    size,
    alignment: int,
    owner_id: string,
) {
    inspection, found := repl_session_inspection(session, handle)
    if !found {
        return
    }
    delete(inspection.snapshot_output)
    delete(inspection.owner_id)
    inspection.snapshot_output = strings.clone(output)
    inspection.size = size
    inspection.alignment = alignment
    inspection.owner_id = strings.clone(owner_id)
    repl_session_record_ownership_event(
        session,
        inspection.handle,
        "retained",
        inspection.generation,
        name = inspection.handle,
        ty = inspection.ty,
        owner_to = inspection.owner_id,
        reason = "inspection snapshot retained",
    )
}

repl_session_clear_inspections :: proc(session: ^Repl_Session) {
    for &inspection in session.inspections {
        repl_inspection_delete(&inspection)
    }
    clear(&session.inspections)
    session.next_inspection = 0
}

repl_session_inspection :: proc(
    session: ^Repl_Session,
    handle: string,
) -> (^Repl_Inspection, bool) {
    for &inspection in session.inspections {
        if inspection.handle == handle {
            return &inspection, true
        }
    }
    return nil, false
}

repl_session_next_inspection :: proc(session: ^Repl_Session) -> (
    handle,
    slot: string,
) {
    session.next_inspection += 1
    return strings.clone(fmt.tprintf("inspection-%d", session.next_inspection)),
           strings.clone(fmt.tprintf("kvist_repl_inspection_%d", session.next_inspection))
}

repl_session_commit_inspection :: proc(
    session: ^Repl_Session,
    handle,
    slot,
    ty,
    abi: string,
    generation: int,
) {
    append(&session.inspections, Repl_Inspection{
        handle = strings.clone(handle),
        slot = strings.clone(slot),
        ty = strings.clone(ty),
        abi = strings.clone(abi),
        generation = generation,
    })
}

repl_session_recent_result_types :: proc(session: ^Repl_Session) -> [dynamic]string {
    result: [dynamic]string
    for i := 0; i < session.result_count; i += 1 {
        append(&result, session.results[i].ty)
    }
    return result
}

repl_session_allocations :: proc(
    session: ^Repl_Session,
) -> (
    allocations: [dynamic]Repl_Allocation,
    known_bytes,
    known_count: int,
) {
    for &binding in session.bindings {
        if binding.allocation_id == "" {
            continue
        }
        append(&allocations, Repl_Allocation{
            allocation_id = binding.allocation_id,
            owner_id = binding.owner_id,
            kind = "binding",
            name = binding.name,
            ty = binding.ty,
            abi = binding.abi,
            generation = binding.generation,
            version = Repl_Optional_Int(binding.version),
            lifecycle = repl_type_lifecycle(binding.ty, binding.abi),
            retained_owner_chain = [1]string{binding.owner_id},
        })
    }
    for result_index in 0..<session.result_count {
        result := &session.results[result_index]
        if result.allocation_id == "" {
            continue
        }
        append(&allocations, Repl_Allocation{
            allocation_id = result.allocation_id,
            owner_id = result.owner_id,
            kind = "result",
            name = result.name,
            ty = result.ty,
            abi = result.abi,
            generation = result.generation,
            lifecycle = result.lifecycle,
            retained_owner_chain = [1]string{result.owner_id},
        })
    }
    for &inspection in session.inspections {
        if inspection.owner_id == "" {
            continue
        }
        append(&allocations, Repl_Allocation{
            allocation_id = inspection.handle,
            owner_id = inspection.owner_id,
            kind = "inspection",
            name = inspection.handle,
            ty = inspection.ty,
            abi = inspection.abi,
            generation = inspection.generation,
            lifecycle =
                repl_type_lifecycle(inspection.ty, inspection.abi),
            retained_owner_chain = [1]string{inspection.owner_id},
            size = Repl_Optional_Int(inspection.size),
            alignment = Repl_Optional_Int(inspection.alignment),
        })
        known_bytes += inspection.size
        known_count += 1
    }
    return
}

repl_session_rotate_result :: proc(
    session: ^Repl_Session,
    ty,
    abi: string,
    generation: int,
) {
    evicted := &session.results[2]
    if session.result_count == len(session.results) &&
       evicted.allocation_id != "" {
        repl_session_record_ownership_event(
            session,
            evicted.allocation_id,
            "evicted",
            generation,
            name = evicted.name,
            ty = evicted.ty,
            owner_from = evicted.owner_id,
            reason = "recent result history exceeded three values",
        )
    }
    repl_result_delete(&session.results[2])
    session.results[2] = session.results[1]
    session.results[1] = session.results[0]
    session.results[0] = Repl_Result{
        slot = 1,
        name = strings.clone("*1"),
        ty = strings.clone(ty),
        abi = strings.clone(abi),
        generation = generation,
        lifecycle = repl_type_lifecycle(ty, abi),
        owner_id = strings.clone("repl-worker"),
        allocation_id =
            strings.clone(fmt.tprintf("result:g%d", generation)),
    }
    if session.result_count < 3 {
        session.result_count += 1
    }
    for i := 1; i < session.result_count; i += 1 {
        session.results[i].slot = i+1
        delete(session.results[i].name)
        session.results[i].name = strings.clone(fmt.tprintf("*%d", i+1))
    }
    repl_session_record_ownership_event(
        session,
        session.results[0].allocation_id,
        "acquired",
        generation,
        name = session.results[0].name,
        ty = session.results[0].ty,
        owner_to = session.results[0].owner_id,
        reason = "evaluation result retained",
    )
}

repl_session_binding_delete :: proc(binding: ^Repl_Session_Binding) {
    delete(binding.name)
    delete(binding.kind)
    delete(binding.abi)
    delete(binding.ty)
    delete(binding.owner_id)
    delete(binding.allocation_id)
    kvist.repl_string_slice_delete(binding.dependencies[:])
    delete(binding.source_path)
    delete(binding.source)
    delete(binding.identity)
    kvist.repl_string_slice_delete(binding.dependency_identities[:])
    for version in binding.versions {
        delete(version.kind)
        delete(version.abi)
        kvist.repl_string_slice_delete(version.dependencies[:])
        delete(version.source_path)
    }
    delete(binding.versions)
    binding^ = {}
}

repl_binding_type_from_abi :: proc(abi: string) -> string {
    value_prefix := "value:"
    var_prefix := "var:"
    start := 0
    if strings.has_prefix(abi, value_prefix) {
        start = len(value_prefix)
    } else if strings.has_prefix(abi, var_prefix) {
        start = len(var_prefix)
    } else {
        return strings.clone("")
    }
    ty := abi[start:]
    if layout := strings.index(ty, "|"); layout >= 0 {
        ty = ty[:layout]
    }
    return strings.clone(ty)
}

repl_debug_local_delete :: proc(local: ^Repl_Debug_Local) {
    delete(local.name)
    delete(local.ty)
    delete(local.ownership)
    delete(local.value)
    delete(local.element_type)
    delete(local.key_type)
    delete(local.value_type)
    for &path in local.paths {
        delete(path.path)
        delete(path.ty)
        delete(path.value)
    }
    delete(local.paths)
    for &path in local.element_paths {
        delete(path.path)
        delete(path.ty)
        delete(path.value)
    }
    delete(local.element_paths)
    for &path in local.map_value_paths {
        delete(path.path)
        delete(path.ty)
        delete(path.value)
    }
    delete(local.map_value_paths)
    local^ = {}
}

repl_debug_local_clone :: proc(local: Repl_Debug_Local) -> Repl_Debug_Local {
    cloned := Repl_Debug_Local{
        name = strings.clone(local.name),
        ty = strings.clone(local.ty),
        mutable = local.mutable,
        ownership = strings.clone(local.ownership),
        lifecycle = local.lifecycle,
        value = strings.clone(local.value),
        element_type = strings.clone(local.element_type),
        key_type = strings.clone(local.key_type),
        value_type = strings.clone(local.value_type),
        capture_limit = local.capture_limit,
        total = local.total,
        truncated = local.truncated,
    }
    for path in local.paths {
        append(&cloned.paths, Repl_Debug_Path{
            path = strings.clone(path.path),
            ty = strings.clone(path.ty),
            value = strings.clone(path.value),
        })
    }
    for path in local.element_paths {
        append(&cloned.element_paths, Repl_Debug_Path{
            path = strings.clone(path.path),
            ty = strings.clone(path.ty),
            value = strings.clone(path.value),
        })
    }
    for path in local.map_value_paths {
        append(&cloned.map_value_paths, Repl_Debug_Path{
            path = strings.clone(path.path),
            ty = strings.clone(path.ty),
            value = strings.clone(path.value),
        })
    }
    return cloned
}

repl_loaded_generation_delete :: proc(generation: ^Repl_Loaded_Generation) {
    delete(generation.source_path)
    delete(generation.map_path)
    delete(generation.library_path)
    for &location in generation.breakpoint_locations {
        delete(location.source_path)
        delete(location.generated_path)
    }
    delete(generation.breakpoint_locations)
    for &frame in generation.pause_points {
        delete(frame.frame_id)
        delete(frame.pause_id)
        delete(frame.definition_name)
        delete(frame.source_path)
        delete(frame.phase)
        for &local in frame.locals {
            repl_debug_local_delete(&local)
        }
        delete(frame.locals)
        for &collection in frame.collections {
            delete(collection.path)
            delete(collection.shape)
            delete(collection.element_type)
            delete(collection.key_type)
            delete(collection.value_type)
        }
        delete(frame.collections)
    }
    delete(generation.pause_points)
    generation^ = {}
}

repl_session_commit_generation :: proc(
    session: ^Repl_Session,
    number: int,
    source_path,
    map_path,
    library_path: string,
    breakpoint_locations: []Repl_Breakpoint_Location,
    pause_points: []Repl_Debug_Frame,
    debug_symbols := false,
) {
    retained_locations: [dynamic]Repl_Breakpoint_Location
    for location in breakpoint_locations {
        retained := location
        retained.source_path = strings.clone(location.source_path)
        retained.generated_path = strings.clone(location.generated_path)
        append(&retained_locations, retained)
    }
    retained_pause_points: [dynamic]Repl_Debug_Frame
    for frame in pause_points {
        retained := frame
        retained.frame_id = strings.clone(frame.frame_id)
        retained.pause_id = strings.clone(frame.pause_id)
        retained.definition_name =
            strings.clone(frame.definition_name)
        retained.source_path = strings.clone(frame.source_path)
        retained.phase = strings.clone(frame.phase)
        retained.locals = nil
        for local in frame.locals {
            append(&retained.locals, repl_debug_local_clone(local))
        }
        append(&retained_pause_points, retained)
    }
    append(&session.generations, Repl_Loaded_Generation{
        generation = number,
        source_path = strings.clone(source_path),
        map_path = strings.clone(map_path),
        library_path = strings.clone(library_path),
        debug_symbols = debug_symbols,
        breakpoint_locations = retained_locations,
        pause_points = retained_pause_points,
    })
    for index := len(session.generations)-1;
        index > 0 &&
        session.generations[index-1].generation >
            session.generations[index].generation;
        index -= 1 {
        session.generations[index-1],
        session.generations[index] =
            session.generations[index],
            session.generations[index-1]
    }
}

repl_session_clear :: proc(session: ^Repl_Session) {
    for definition in session.definitions {
        delete(definition)
    }
    clear(&session.definitions)
    for &binding in session.bindings {
        repl_session_binding_delete(&binding)
    }
    clear(&session.bindings)
    repl_session_clear_results(session)
    repl_session_clear_inspections(session)
    for &generation in session.generations {
        repl_loaded_generation_delete(&generation)
    }
    clear(&session.generations)
    for &event in session.ownership_events {
        repl_ownership_event_delete(&event)
    }
    clear(&session.ownership_events)
    session.next_ownership_event = 0
    for &compiled in session.compiled_generations {
        delete(compiled.library_path)
        delete(compiled.emitted_source)
        delete(compiled.warning_text)
        for ty in compiled.resident_recent_result_types {
            delete(ty)
        }
        repl_diagnostic_slice_delete(&compiled.diagnostics)
        for &record in compiled.dependency_files {
            delete_dependency_file_fingerprint(&record)
        }
        delete(compiled.dependency_files)
        for record in compiled.dependency_directories {
            delete(record.path)
        }
        delete(compiled.dependency_directories)
    }
    clear(&session.compiled_generations)
    for &invoke in session.resident_scalar_invokes {
        delete(invoke.name)
        delete(invoke.signature)
        delete(invoke.result_abi)
    }
    clear(&session.resident_scalar_invokes)
}

repl_session_drop_binding :: proc(
    session: ^Repl_Session,
    name: string,
    generation := 0,
) -> (message: string, ok: bool) {
    binding_index, found := repl_binding_index(session, name)
    if !found {
        return strings.clone(fmt.tprintf("unknown REPL binding: %s", name)), false
    }
    dependents := repl_collect_dependents(session, name)
    defer delete(dependents)
    if len(dependents) > 0 {
        return strings.clone(
            fmt.tprintf(
                "cannot drop %s while %d session binding(s) depend on it",
                name,
                len(dependents),
            ),
        ), false
    }
    binding := &session.bindings[binding_index]
    repl_session_record_ownership_event(
        session,
        binding.allocation_id,
        "dropped",
        generation,
        name = binding.name,
        ty = binding.ty,
        owner_from = binding.owner_id,
        reason = "binding explicitly dropped",
    )
    for i := len(session.definitions)-1; i >= 0; i -= 1 {
        filtered := kvist.repl_without_definition_source(
            session.definitions[i],
            name,
        )
        delete(session.definitions[i])
        if strings.trim_space(filtered) == "" {
            delete(filtered)
            ordered_remove(&session.definitions, i)
        } else {
            session.definitions[i] = filtered
        }
    }
    repl_session_binding_delete(&session.bindings[binding_index])
    ordered_remove(&session.bindings, binding_index)
    return "", true
}

repl_session_delete :: proc(session: ^Repl_Session) {
    repl_session_clear(session)
    delete(session.definitions)
    delete(session.bindings)
    delete(session.inspections)
    delete(session.generations)
    delete(session.ownership_events)
    delete(session.compiled_generations)
    delete(session.resident_scalar_invokes)
    session^ = {}
}

repl_session_source :: proc(session: ^Repl_Session) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for definition in session.definitions {
        strings.write_string(&builder, definition)
        strings.write_byte(&builder, '\n')
    }
    return strings.clone(strings.to_string(builder))
}

repl_source_is_unchanged_functions :: proc(
    input,
    source,
    source_path: string,
    session: ^Repl_Session,
    defer_debug_values := false,
) -> bool {
    normalized_source, _, normalized :=
        kvist.repl_normalize_source_path(
            input,
            source,
            source_path if source_path != "" else input,
        )
    if !normalized {
        return false
    }
    defer delete(normalized_source)
    definitions := kvist.repl_persistent_definitions_source(normalized_source)
    defer delete(definitions)
    if strings.trim_space(definitions) == "" ||
       strings.trim_space(definitions) != strings.trim_space(normalized_source) {
        return false
    }
    infos := kvist.repl_definition_infos(definitions)
    defer kvist.repl_definition_info_slice_delete(infos[:])
    if len(infos) == 0 {
        return false
    }
    for info in infos {
        if info.kind != "defn" && info.kind != "defn-" {
            return false
        }
        binding_index, found := repl_binding_index(session, info.name)
        if !found {
            return false
        }
        binding := &session.bindings[binding_index]
        if binding.stale ||
           binding.kind != info.kind ||
           binding.source != info.source ||
           binding.direct_scalar_invoke != defer_debug_values {
            return false
        }
    }
    return true
}

repl_symbol_slice_delete :: proc(symbols: ^[dynamic]Repl_Symbol) {
    for symbol in symbols^ {
        delete(symbol.kind)
        delete(symbol.name)
        delete(symbol.detail)
        delete(symbol.signature)
        delete(symbol.doc)
        delete(symbol.file)
    }
    delete(symbols^)
    symbols^ = nil
}

repl_diagnostic_slice_delete :: proc(
    diagnostics: ^[dynamic]Repl_Diagnostic,
) {
    for diagnostic in diagnostics^ {
        delete(diagnostic.severity)
        delete(diagnostic.code)
        delete(diagnostic.confidence)
        delete(diagnostic.phase)
        delete(diagnostic.message)
        delete(diagnostic.source_path)
    }
    delete(diagnostics^)
    diagnostics^ = nil
}

repl_diagnostic_clone :: proc(
    diagnostic: Repl_Diagnostic,
) -> Repl_Diagnostic {
    cloned := diagnostic
    cloned.severity = strings.clone(diagnostic.severity)
    cloned.code = strings.clone(diagnostic.code)
    cloned.confidence = strings.clone(diagnostic.confidence)
    cloned.phase = strings.clone(diagnostic.phase)
    cloned.message = strings.clone(diagnostic.message)
    cloned.source_path = strings.clone(diagnostic.source_path)
    return cloned
}

repl_diagnostic_range :: proc(
    source: string,
    span: kvist.Span,
    start_line,
    start_column: int,
) -> (line, column, end_line, end_column: int) {
    local_line, local_column, _, _ :=
        kvist.source_position(source, span.start)
    local_end_line, local_end_column, _, _ :=
        kvist.source_position(source, max(span.end, span.start))
    line = max(start_line, 1)+local_line-1
    end_line = max(start_line, 1)+local_end_line-1
    column = local_column
    end_column = local_end_column
    if local_line == 1 {
        column += max(start_column, 1)-1
    }
    if local_end_line == 1 {
        end_column += max(start_column, 1)-1
    }
    return
}

repl_normalized_symbol_name :: proc(name: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for ch in name {
        strings.write_rune(&builder, '/' if ch == '.' else ch)
    }
    return strings.clone(strings.to_string(builder))
}

repl_symbol_matches :: proc(name, query: string, prefix: bool) -> bool {
    if query == "" {
        return true
    }
    normalized_name := repl_normalized_symbol_name(name)
    defer delete(normalized_name)
    normalized_query := repl_normalized_symbol_name(query)
    defer delete(normalized_query)
    if prefix {
        if strings.has_prefix(name, query) ||
           strings.has_prefix(normalized_name, normalized_query) {
            return true
        }
        if !strings.contains_any(query, "./") {
            slash := strings.last_index_any(normalized_name, "/")
            bare := normalized_name
            if slash >= 0 && slash+1 < len(normalized_name) {
                bare = normalized_name[slash+1:]
            }
            return strings.has_prefix(bare, normalized_query)
        }
        return false
    }
    if normalized_name == normalized_query {
        return true
    }
    return len(normalized_name) > len(normalized_query)+1 &&
           strings.has_suffix(normalized_name, normalized_query) &&
           normalized_name[len(normalized_name)-len(normalized_query)-1] == '/'
}

repl_tooling_symbols :: proc(
    input,
    source_path: string,
    session: ^Repl_Session,
    overlay,
    query: string,
    prefix := false,
) -> (
    symbols: [dynamic]Repl_Symbol,
    message: string,
    ok: bool,
) {
    tooling_path := source_path
    if tooling_path == "" {
        tooling_path = input
    }
    source := overlay
    input_data: []byte
    if source == "" {
        read_data, read_err :=
            os.read_entire_file_from_path(tooling_path, context.allocator)
        if read_err != nil {
            return nil, strings.clone(
                fmt.tprintf("could not read file: %s", tooling_path),
            ), false
        }
        input_data = read_data
        source = string(input_data)
    }
    defer if input_data != nil {
        delete(input_data)
    }

    retained := repl_session_source(session)
    defer delete(retained)
    combined := strings.builder_make()
    defer strings.builder_destroy(&combined)
    strings.write_string(&combined, source)
    strings.write_byte(&combined, '\n')
    strings.write_string(&combined, retained)
    output, compile_err, compiled :=
        kvist.editor_symbols_source(tooling_path, strings.to_string(combined))
    if !compiled {
        return nil, strings.clone(compile_err.message), false
    }
    defer delete(output)

    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line, line_index in lines {
        if line_index == 0 || line == "" {
            continue
        }
        fields, valid := kvist.symbols_split_record_fields(line)
        if !valid || len(fields) < 7 {
            delete(fields)
            continue
        }
        if !repl_symbol_matches(fields[1], query, prefix) {
            delete(fields)
            continue
        }
        line_number, valid_line := strconv.parse_int(fields[2])
        column_number, valid_column := strconv.parse_int(fields[3])
        if !valid_line || !valid_column {
            delete(fields)
            continue
        }
        symbol_file := tooling_path
        if len(fields) >= 8 && fields[7] != "" {
            symbol_file = fields[7]
        }
        append(&symbols, Repl_Symbol{
            kind = strings.clone(fields[0]),
            name = strings.clone(fields[1]),
            line = line_number,
            column = column_number,
            detail = strings.clone(fields[4]),
            signature = strings.clone(fields[5]),
            doc = kvist.symbols_unescape_doc_text(fields[6]),
            file = strings.clone(symbol_file),
        })
        delete(fields)
    }
    return symbols, "", true
}

repl_is_tooling_op :: proc(op: string) -> bool {
    return op == "complete" ||
           op == "lookup" ||
           op == "documentation" ||
           op == "xref"
}

repl_emit_tooling_request :: proc(
    input: string,
    session: ^Repl_Session,
    request: ^Repl_Request,
    generation: int,
    attached := false,
    application_generation := 0,
) {
    symbols: [dynamic]Repl_Symbol
    message := ""
    tooling_ok := input != "" && session != nil
    if tooling_ok {
        symbols, message, tooling_ok =
            repl_tooling_symbols(
                input,
                request.source_path,
                session,
                request.source,
                request.name,
                request.op == "complete",
            )
    } else {
        message = strings.clone(
            "session tooling requires a context file",
        )
    }
    event_application_generation: Repl_Optional_Int
    event_attached_generation: Repl_Optional_Int
    if attached {
        event_application_generation =
            Repl_Optional_Int(application_generation)
        event_attached_generation = Repl_Optional_Int(generation)
    }
    result_kind := request.op
    if request.op == "complete" {
        result_kind = "completions"
    }
    repl_emit_json_event(Repl_Event{
        protocol_version = REPL_PROTOCOL_VERSION,
        id = request.id,
        kind = result_kind,
        success = tooling_ok,
        generation = generation,
        message = message,
        symbols = symbols[:],
        attached = attached,
        application_generation = event_application_generation,
        attached_generation = event_attached_generation,
    })
    repl_emit_json_event(Repl_Event{
        protocol_version = REPL_PROTOCOL_VERSION,
        id = request.id,
        kind = "complete",
        success = tooling_ok,
        generation = generation,
        message = message,
        attached = attached,
        application_generation = event_application_generation,
        attached_generation = event_attached_generation,
    })
    repl_symbol_slice_delete(&symbols)
    if message != "" {
        delete(message)
    }
}

repl_binding_index :: proc(session: ^Repl_Session, name: string) -> (int, bool) {
    for binding, idx in session.bindings {
        if binding.name == name {
            return idx, true
        }
    }
    return -1, false
}

repl_binding_version :: proc(
    session: ^Repl_Session,
    name: string,
    requested: Repl_Optional_Int,
) -> (
    binding: ^Repl_Session_Binding,
    version: ^Repl_Binding_Version,
    message: string,
    ok: bool,
) {
    binding_index, found := repl_binding_index(session, name)
    if !found {
        return nil, nil,
            strings.clone(fmt.tprintf("unknown REPL binding: %s", name)),
            false
    }
    binding = &session.bindings[binding_index]
    if requested_version, has_version := requested.(int); has_version {
        if requested_version <= 0 {
            return nil, nil,
                strings.clone("definition version must be positive"),
                false
        }
        for &candidate in binding.versions {
            if candidate.version == requested_version {
                return binding, &candidate, "", true
            }
        }
        return nil, nil,
            strings.clone(
                fmt.tprintf(
                    "unknown REPL binding version: %s %d",
                    name,
                    requested_version,
                ),
            ),
            false
    }
    if len(binding.versions) == 0 {
        return nil, nil,
            strings.clone(fmt.tprintf("REPL binding has no versions: %s", name)),
            false
    }
    return binding, &binding.versions[len(binding.versions)-1], "", true
}

repl_definition_source_range :: proc(
    source: string,
    start,
    end,
    submitted_start_line,
    submitted_start_column: int,
) -> (
    start_line,
    start_column,
    end_line,
    end_column: int,
) {
    local_start_line, local_start_column, _, _ :=
        kvist.source_position(source, start)
    local_end_line, local_end_column, _, _ :=
        kvist.source_position(source, end)
    start_line = max(submitted_start_line, 1)+local_start_line-1
    end_line = max(submitted_start_line, 1)+local_end_line-1
    start_column = local_start_column
    end_column = local_end_column
    if local_start_line == 1 {
        start_column += max(submitted_start_column, 1)-1
    }
    if local_end_line == 1 {
        end_column += max(submitted_start_column, 1)-1
    }
    return
}

repl_frame_in_source_range :: proc(
    frame: ^Repl_Debug_Frame,
    source_path: string,
    start_line,
    start_column,
    end_line,
    end_column: int,
) -> bool {
    if frame.source_path != source_path ||
       frame.line < start_line ||
       frame.line > end_line {
        return false
    }
    if frame.line == start_line && frame.column < start_column {
        return false
    }
    if frame.line == end_line && frame.column > end_column {
        return false
    }
    return true
}

repl_annotate_definition_frames :: proc(
    session: ^Repl_Session,
    binding: ^Repl_Session_Binding,
    generation: int,
    submitted_source_path: string,
    submitted_start_line,
    submitted_start_column,
    submitted_end_line,
    submitted_end_column: int,
    remap_location: bool,
) {
    for &loaded_generation in session.generations {
        if loaded_generation.generation != generation {
            continue
        }
        for &frame in loaded_generation.pause_points {
            if !repl_frame_in_source_range(
                &frame,
                submitted_source_path,
                submitted_start_line,
                submitted_start_column,
                submitted_end_line,
                submitted_end_column,
            ) {
                continue
            }
            delete(frame.definition_name)
            frame.definition_name = strings.clone(binding.name)
            frame.definition_version =
                Repl_Optional_Int(binding.version)
            if remap_location {
                relative_line := frame.line-submitted_start_line
                frame.line = binding.source_start_line+relative_line
                if relative_line == 0 {
                    frame.column =
                        binding.source_start_column+
                        frame.column-submitted_start_column
                }
                delete(frame.source_path)
                frame.source_path = strings.clone(binding.source_path)
            }
        }
        return
    }
}

repl_definition_location_event :: proc(
    id: string,
    logical_generation: int,
    binding: ^Repl_Session_Binding,
    version: ^Repl_Binding_Version,
) -> Repl_Event {
    return Repl_Event{
        protocol_version = REPL_PROTOCOL_VERSION,
        id = id,
        kind = "definition-location",
        success = true,
        generation = logical_generation,
        name = binding.name,
        definition_kind = version.kind,
        version = Repl_Optional_Int(version.version),
        definition_generation =
            Repl_Optional_Int(version.generation),
        abi = version.abi,
        source_path = version.source_path,
        line = Repl_Optional_Int(version.source_start_line),
        column = Repl_Optional_Int(version.source_start_column),
        end_line = Repl_Optional_Int(version.source_end_line),
        end_column = Repl_Optional_Int(version.source_end_column),
    }
}

repl_abi_payload :: proc(abi: string) -> string {
    separator := strings.index(abi, ":")
    if separator < 0 || separator+1 >= len(abi) {
        return ""
    }
    return abi[separator+1:]
}

repl_annotate_inspection_definition :: proc(
    event: ^Repl_Event,
    session: ^Repl_Session,
    inspected_abi: string,
) {
    inspected_payload := repl_abi_payload(inspected_abi)
    if inspected_payload == "" {
        return
    }
    for &binding in session.bindings {
        for offset in 0..<len(binding.versions) {
            version :=
                &binding.versions[len(binding.versions)-1-offset]
            if !strings.has_prefix(version.abi, "type:") ||
               repl_abi_payload(version.abi) != inspected_payload {
                continue
            }
            event.name = binding.name
            event.definition_kind = version.kind
            event.version = Repl_Optional_Int(version.version)
            event.definition_generation =
                Repl_Optional_Int(version.generation)
            event.source_path = version.source_path
            event.line =
                Repl_Optional_Int(version.source_start_line)
            event.column =
                Repl_Optional_Int(version.source_start_column)
            event.end_line =
                Repl_Optional_Int(version.source_end_line)
            event.end_column =
                Repl_Optional_Int(version.source_end_column)
            return
        }
    }
}

repl_emit_cached_inspection :: proc(
    id: string,
    session: ^Repl_Session,
    inspection: ^Repl_Inspection,
    generation: int,
    attached := false,
    application_generation := 0,
) -> bool {
    if inspection == nil || inspection.snapshot_output == "" {
        return false
    }
    schema := repl_inspection_schema(inspection.ty, inspection.abi)
    defer delete(schema.members)
    lifecycle := repl_type_lifecycle(inspection.ty, inspection.abi)
    entries: [dynamic]Repl_Inspection_Entry
    defer repl_inspection_entries_delete(entries[:])
    total := 0
    has_page :=
        strings.has_prefix(
            inspection.snapshot_output,
            REPL_PAGE_TOTAL_MARKER,
        )
    if has_page {
        parsed := false
        entries, total, parsed =
            repl_parse_inspection_page(inspection.snapshot_output)
        if !parsed {
            return false
        }
    }
    event := Repl_Event{
        protocol_version = REPL_PROTOCOL_VERSION,
        id = id,
        kind = "inspection",
        success = true,
        generation = generation,
        text = "" if has_page else inspection.snapshot_output,
        ty = inspection.ty,
        abi = inspection.abi,
        handle = inspection.handle,
        shape = schema.shape,
        element_type = schema.element_type,
        key_type = schema.key_type,
        value_type = schema.value_type,
        length = &schema.length if schema.has_length else nil,
        members = schema.members[:],
        offset = Repl_Optional_Int(0) if has_page else {},
        limit =
            Repl_Optional_Int(REPL_DEFAULT_PAGE_LIMIT) if has_page else {},
        total = Repl_Optional_Int(total) if has_page else {},
        entries = entries[:],
        lifecycle = Repl_Optional_Lifecycle(lifecycle),
        owner_id = inspection.owner_id,
        allocation_id = inspection.handle,
        retained_owner_chain = []string{inspection.owner_id},
        size = Repl_Optional_Int(inspection.size),
        alignment = Repl_Optional_Int(inspection.alignment),
        attached = attached,
        application_generation =
            Repl_Optional_Int(application_generation) if attached else {},
        attached_generation =
            Repl_Optional_Int(generation) if attached else {},
    }
    repl_annotate_inspection_definition(
        &event,
        session,
        inspection.abi,
    )
    repl_emit_json_event(event)
    return true
}

repl_name_in_slice :: proc(name: string, names: []string) -> bool {
    for candidate in names {
        if candidate == name {
            return true
        }
    }
    return false
}

repl_info_is_latest :: proc(infos: []kvist.Repl_Definition_Info, index: int) -> bool {
    for later in infos[index+1:] {
        if later.name == infos[index].name {
            return false
        }
    }
    return true
}

repl_session_commit :: proc(
    session: ^Repl_Session,
    definitions,
    submitted_source,
    emitted_source: string,
    generation: int,
    submitted_source_path := "",
    submitted_start_line := 1,
    submitted_start_column := 1,
    preserve_existing_locations := false,
    direct_scalar_invoke := false,
) {
    append(&session.definitions, strings.clone(definitions))
    infos := kvist.repl_definition_infos(definitions)
    defer kvist.repl_definition_info_slice_delete(infos[:])
    submitted_infos := kvist.repl_definition_infos(submitted_source)
    defer kvist.repl_definition_info_slice_delete(submitted_infos[:])
    compiled_names: [dynamic]string
    defer delete(compiled_names)

    for info, info_index in infos {
        if !repl_info_is_latest(infos[:], info_index) {
            continue
        }
        append(&compiled_names, info.name)
        abi := kvist.repl_registered_abi(emitted_source, info.name)
        identity := info.source if abi == "" else abi
        binding_ty := repl_binding_type_from_abi(abi)
        location_info := info
        if info_index < len(submitted_infos) {
            location_info = submitted_infos[info_index]
        }
        source_start_line,
        source_start_column,
        source_end_line,
        source_end_column :=
            repl_definition_source_range(
                submitted_source,
                location_info.start,
                location_info.end,
                submitted_start_line,
                submitted_start_column,
            )
        binding_index, found := repl_binding_index(session, info.name)
        if found {
            binding := &session.bindings[binding_index]
            repl_session_record_ownership_event(
                session,
                binding.allocation_id,
                "superseded",
                generation,
                name = binding.name,
                ty = binding.ty,
                owner_from = binding.owner_id,
                reason = "binding definition replaced",
            )
            delete(binding.kind)
            delete(binding.abi)
            delete(binding.ty)
            delete(binding.owner_id)
            delete(binding.allocation_id)
            delete(binding.source)
            delete(binding.identity)
            kvist.repl_string_slice_delete(binding.dependencies[:])
            kvist.repl_string_slice_delete(binding.dependency_identities[:])
            binding.dependencies = nil
            binding.dependency_identities = nil
            binding.kind = strings.clone(info.kind)
            binding.version += 1
            binding.generation = generation
            binding.abi = strings.clone(abi)
            binding.ty = strings.clone(binding_ty)
            if binding.ty != "" {
                binding.lifecycle =
                    Repl_Optional_Lifecycle(
                        repl_type_lifecycle(binding.ty, abi),
                    )
            } else {
                binding.lifecycle = {}
            }
            if binding.ty != "" {
                binding.owner_id = strings.clone("repl-worker")
                binding.allocation_id =
                    strings.clone(
                        fmt.tprintf(
                            "binding:%s:v%d",
                            info.name,
                            binding.version,
                        ),
                    )
            }
            binding.source = strings.clone(info.source)
            binding.identity = strings.clone(identity)
            binding.stale = false
            binding.direct_scalar_invoke = direct_scalar_invoke
            if !preserve_existing_locations ||
               binding.source_path == "" {
                delete(binding.source_path)
                binding.source_path =
                    strings.clone(submitted_source_path)
                binding.source_start_line = source_start_line
                binding.source_end_line = source_end_line
                binding.source_start_column = source_start_column
                binding.source_end_column = source_end_column
            }
        } else {
            append(&session.bindings, Repl_Session_Binding{
                name = strings.clone(info.name),
                kind = strings.clone(info.kind),
                version = 1,
                generation = generation,
                abi = strings.clone(abi),
                ty = strings.clone(binding_ty),
                lifecycle =
                    Repl_Optional_Lifecycle(
                        repl_type_lifecycle(binding_ty, abi),
                    ) if binding_ty != "" else {},
                owner_id =
                    strings.clone("repl-worker") if
                        strings.has_prefix(abi, "value:") ||
                        strings.has_prefix(abi, "var:") else "",
                allocation_id =
                    strings.clone(
                        fmt.tprintf("binding:%s:v1", info.name),
                    ) if
                        strings.has_prefix(abi, "value:") ||
                        strings.has_prefix(abi, "var:") else "",
                source_path = strings.clone(submitted_source_path),
                source_start_line = source_start_line,
                source_start_column = source_start_column,
                source_end_line = source_end_line,
                source_end_column = source_end_column,
                source = strings.clone(info.source),
                identity = strings.clone(identity),
                direct_scalar_invoke = direct_scalar_invoke,
            })
        }
        committed_binding_index, committed :=
            repl_binding_index(session, info.name)
        if committed {
            committed_binding :=
                &session.bindings[committed_binding_index]
            repl_session_record_ownership_event(
                session,
                committed_binding.allocation_id,
                "acquired",
                generation,
                name = committed_binding.name,
                ty = committed_binding.ty,
                owner_to = committed_binding.owner_id,
                reason = "binding definition retained",
            )
            repl_annotate_definition_frames(
                session,
                committed_binding,
                generation,
                submitted_source_path,
                source_start_line,
                source_start_column,
                source_end_line,
                source_end_column,
                preserve_existing_locations,
            )
        }
        delete(binding_ty)
        delete(abi)
    }

    candidate_names := make([dynamic]string, 0, len(session.bindings))
    defer delete(candidate_names)
    for binding in session.bindings {
        append(&candidate_names, binding.name)
    }
    for compiled_name in compiled_names {
        binding_index, found := repl_binding_index(session, compiled_name)
        if !found {
            continue
        }
        binding := &session.bindings[binding_index]
        dependencies := kvist.repl_definition_dependencies(binding.source, candidate_names[:])
        for i := len(dependencies)-1; i >= 0; i -= 1 {
            if dependencies[i] == binding.name {
                delete(dependencies[i])
                unordered_remove(&dependencies, i)
            }
        }
        binding.dependencies = dependencies
        for dependency in binding.dependencies {
            dependency_index, dependency_found := repl_binding_index(session, dependency)
            if dependency_found {
                append(
                    &binding.dependency_identities,
                    strings.clone(session.bindings[dependency_index].identity),
                )
            } else {
                append(&binding.dependency_identities, strings.clone(""))
            }
        }
    }

    for compiled_name in compiled_names {
        binding_index, found := repl_binding_index(session, compiled_name)
        if !found {
            continue
        }
        binding := &session.bindings[binding_index]
        if binding.abi == "" {
            identity_builder := strings.builder_make()
            strings.write_string(&identity_builder, binding.source)
            for dependency, dependency_index in binding.dependencies {
                strings.write_byte(&identity_builder, '\n')
                strings.write_string(&identity_builder, dependency)
                strings.write_byte(&identity_builder, '=')
                if dependency_index < len(binding.dependency_identities) {
                    strings.write_string(
                        &identity_builder,
                        binding.dependency_identities[dependency_index],
                    )
                }
            }
            delete(binding.identity)
            binding.identity =
                strings.clone(strings.to_string(identity_builder))
            strings.builder_destroy(&identity_builder)
        }
        version := Repl_Binding_Version{
            version = binding.version,
            generation = binding.generation,
            kind = strings.clone(binding.kind),
            abi = strings.clone(binding.abi),
            source_path = strings.clone(binding.source_path),
            source_start_line = binding.source_start_line,
            source_start_column = binding.source_start_column,
            source_end_line = binding.source_end_line,
            source_end_column = binding.source_end_column,
        }
        for dependency in binding.dependencies {
            append(&version.dependencies, strings.clone(dependency))
        }
        append(&binding.versions, version)
    }

    for &binding in session.bindings {
        binding.stale = false
        for dependency, dependency_index in binding.dependencies {
            current_index, found := repl_binding_index(session, dependency)
            if !found ||
               dependency_index >= len(binding.dependency_identities) ||
               session.bindings[current_index].identity !=
                   binding.dependency_identities[dependency_index] {
                binding.stale = true
                break
            }
        }
    }
    state_changed := true
    for state_changed {
        state_changed = false
        for &binding in session.bindings {
            if binding.stale {
                continue
            }
            for dependency in binding.dependencies {
                dependency_index, found := repl_binding_index(session, dependency)
                if found && session.bindings[dependency_index].stale {
                    binding.stale = true
                    state_changed = true
                    break
                }
            }
        }
    }
}

repl_delete_request :: proc(request: ^Repl_Request) {
    if request.id != "" {
        delete(request.id)
    }
    if request.op != "" {
        delete(request.op)
    }
    if request.name != "" {
        delete(request.name)
    }
    if request.source != "" {
        delete(request.source)
    }
    if request.handle != "" {
        delete(request.handle)
    }
    kvist.repl_string_slice_delete(request.path[:])
    if request.key_source != "" {
        delete(request.key_source)
    }
    if request.source_path != "" {
        delete(request.source_path)
    }
    if request.pause_id != "" {
        delete(request.pause_id)
    }
    if request.abi != "" {
        delete(request.abi)
    }
    request^ = {}
}

repl_collect_dependents :: proc(
    session: ^Repl_Session,
    name: string,
    only_stale := false,
) -> [dynamic]Repl_Session_Binding {
    dependents: [dynamic]Repl_Session_Binding
    frontier: [dynamic]string
    defer delete(frontier)
    append(&frontier, name)
    frontier_index := 0
    for frontier_index < len(frontier) {
        dependency := frontier[frontier_index]
        frontier_index += 1
        for binding in session.bindings {
            if only_stale && !binding.stale {
                continue
            }
            if !repl_name_in_slice(dependency, binding.dependencies[:]) {
                continue
            }
            already_added := false
            for existing in dependents {
                if existing.name == binding.name {
                    already_added = true
                    break
                }
            }
            if already_added {
                continue
            }
            append(&dependents, binding)
            append(&frontier, binding.name)
        }
    }
    return dependents
}

repl_refresh_dependents_source :: proc(
    session: ^Repl_Session,
    name: string,
) -> (source: string, message: string, ok: bool) {
    if _, found := repl_binding_index(session, name); !found {
        return "", strings.clone(fmt.tprintf("unknown REPL binding: %s", name)), false
    }
    dependents := repl_collect_dependents(session, name, true)
    defer delete(dependents)
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for binding in dependents {
        if binding.kind != "defn" {
            continue
        }
        strings.write_string(&builder, binding.source)
        strings.write_byte(&builder, '\n')
    }
    return strings.clone(strings.to_string(builder)), "", true
}

repl_refresh_binding_source :: proc(
    session: ^Repl_Session,
    name: string,
) -> (source: string, message: string, ok: bool) {
    binding_index, found := repl_binding_index(session, name)
    if !found {
        return "", strings.clone(fmt.tprintf("unknown REPL binding: %s", name)), false
    }
    binding := session.bindings[binding_index]
    if binding.kind != "defn" {
        return "", strings.clone(
            "refresh only recompiles functions; re-evaluate value declarations explicitly",
        ), false
    }
    return strings.clone(binding.source), "", true
}

repl_emit_json_event :: proc(event: Repl_Event) {
    bytes, err := json.marshal(event)
    if err != nil {
        fmt.eprintln(`{"protocol_version":1,"kind":"protocol-error","success":false,"message":"failed to encode event"}`)
        return
    }
    defer delete(bytes)
    fmt.println(string(bytes))
    _ = os.flush(os.stdout)
}

repl_debug_event :: proc(
    id,
    kind: string,
    worker: ^Repl_Worker_Process,
    epoch,
    generation: int,
) -> Repl_Event {
    return Repl_Event{
        protocol_version = REPL_PROTOCOL_VERSION,
        id = id,
        kind = kind,
        success = worker.alive,
        generation = generation,
        worker_pid =
            Repl_Optional_Int(worker.process.pid) if worker.alive else {},
        worker_epoch = Repl_Optional_Int(epoch),
        capabilities = REPL_DEBUG_CAPABILITIES[:],
    }
}

repl_inspect_source :: proc(
    input,
    source: string,
    session: ^Repl_Session,
    macro_only: bool,
    no_print: bool,
) -> (text, message: string, ok: bool) {
    input_data, read_err :=
        os.read_entire_file_from_path(input, context.allocator)
    if read_err != nil {
        return "", strings.clone(fmt.tprintf("could not read file: %s", input)), false
    }
    defer delete(input_data)

    if macro_only {
        retained_source := repl_session_source(session)
        defer delete(retained_source)
        combined := strings.builder_make()
        defer strings.builder_destroy(&combined)
        strings.write_string(&combined, string(input_data))
        strings.write_byte(&combined, '\n')
        strings.write_string(&combined, retained_source)
        result, compile_err, expanded :=
            kvist.macroexpand_eval_source_with_map(
                strings.to_string(combined),
                source,
                input,
            )
        if !expanded {
            diagnostic := kvist.format_eval_compile_error(
                input,
                string(input_data),
                source,
                compile_err,
            )
            return "", diagnostic, false
        }
        defer kvist.source_map_slice_delete(result.source_map)
        return result.output, "", true
    }

    retained_source := repl_session_source(session)
    defer delete(retained_source)
    recent_result_types := repl_session_recent_result_types(session)
    defer delete(recent_result_types)
    result, compile_err, expanded := kvist.compile_eval_path_with_map(
        input,
        source,
        no_print,
        repl_generation = true,
        repl_session_source = retained_source,
        repl_recent_result_types = recent_result_types[:],
    )
    if !expanded {
        diagnostic := kvist.format_eval_compile_error(
            input,
            string(input_data),
            source,
            compile_err,
        )
        return "", diagnostic, false
    }
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    return result.output, "", true
}

repl_trim_line :: proc(line: string) -> string {
    end := len(line)
    if end > 0 && line[end-1] == '\n' {
        end -= 1
    }
    if end > 0 && line[end-1] == '\r' {
        end -= 1
    }
    return line[:end]
}

repl_read_line :: proc(reader: ^bufio.Reader) -> (line: string, ok: bool) {
    value, err := bufio.reader_read_string(reader, '\n')
    if len(value) == 0 && err != nil {
        return "", false
    }
    return value, true
}

repl_worker_command :: proc() -> int {
    reader := bufio.Reader{}
    bufio.reader_init(&reader, os.to_reader(os.stdin))
    defer bufio.reader_destroy(&reader)

    worker := kvist_repl.Worker{}
    worker.input_reader = &reader
    worker.emit_output_to_stdout = true
    defer kvist_repl.worker_delete(&worker)

    for {
        raw, ok := repl_read_line(&reader)
        if !ok {
            return 0
        }
        line := repl_trim_line(raw)
        if line == "__quit__" {
            delete(raw)
            return 0
        }
        if strings.has_prefix(line, "__trace_next__\t") {
            fields := strings.split(line, "\t", context.temp_allocator)
            if len(fields) == 3 {
                if limit, parsed := strconv.parse_int(fields[1]);
                   parsed && limit > 0 {
                    value_limit, value_limit_ok :=
                        strconv.parse_int(fields[2])
                    if value_limit_ok && value_limit >= 0 {
                        kvist_repl.worker_trace_next(
                            &worker,
                            limit,
                            value_limit,
                        )
                    }
                }
            }
            delete(raw)
            continue
        }
        if strings.has_prefix(line, "__checkpoint__\t") ||
           strings.has_prefix(line, "__checkpoint_restore__\t") ||
           strings.has_prefix(line, "__checkpoint_drop__\t") {
            fields := strings.split(line, "\t", context.temp_allocator)
            command_ok := len(fields) == 2
            name := ""
            if command_ok {
                name, command_ok = repl_debug_hex_decode(fields[1])
            }
            count := 0
            message := ""
            operation_ok := false
            if command_ok {
                switch fields[0] {
                case "__checkpoint__":
                    count, message, operation_ok =
                        kvist_repl.worker_checkpoint_capture(&worker, name)
                case "__checkpoint_restore__":
                    count, message, operation_ok =
                        kvist_repl.worker_checkpoint_restore(&worker, name)
                case "__checkpoint_drop__":
                    message, operation_ok =
                        kvist_repl.worker_checkpoint_drop(&worker, name)
                }
            } else {
                message = strings.clone("invalid checkpoint worker command")
            }
            encoded_message := "-"
            owned_encoded_message := ""
            if message != "" {
                owned_encoded_message = repl_debug_hex_encode(message)
                encoded_message = owned_encoded_message
            }
            count_text := fmt.tprintf("%d", count)
            _, _ = os.write_strings(
                os.stdout,
                REPL_WORKER_CHECKPOINT_MARKER,
                "ok" if operation_ok else "error",
                "\t",
                count_text,
                "\t",
                encoded_message,
                "\n",
            )
            _ = os.flush(os.stdout)
            // Generated codecs run with their dynamic library's runtime
            // context. Retain these tiny command allocations until worker
            // exit instead of reclaiming them across that allocator boundary.
            continue
        }
        if line == "__checkpoints__" {
            for checkpoint in worker.checkpoints {
                encoded_name := repl_debug_hex_encode(checkpoint.name)
                count_text := fmt.tprintf("%d", len(checkpoint.entries))
                _, _ = os.write_strings(
                    os.stdout,
                    REPL_WORKER_CHECKPOINT_ITEM_MARKER,
                    encoded_name,
                    "\t",
                    count_text,
                    "\n",
                )
            }
            _, _ = os.write_strings(
                os.stdout,
                REPL_WORKER_CHECKPOINTS_END_MARKER,
                "\n",
            )
            _ = os.flush(os.stdout)
            continue
        }
        if line == "__allocation_stats__" {
            stats := kvist_repl.worker_allocation_stats(&worker)
            _ = fmt.fprintf(
                os.stdout,
                "%s%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n",
                REPL_WORKER_ALLOCATION_STATS_MARKER,
                stats.live_allocations,
                stats.live_bytes,
                stats.total_allocations,
                stats.total_allocated_bytes,
                stats.total_frees,
                stats.total_freed_bytes,
                stats.managed_live_allocations,
                stats.managed_live_bytes,
                stats.managed_peak_bytes,
                stats.managed_total_allocations,
                stats.managed_total_allocated_bytes,
                stats.managed_total_frees,
                stats.managed_total_freed_bytes,
            )
            _ = os.flush(os.stdout)
            delete(raw)
            continue
        }
        if line == "__physical_allocations__" {
            allocations :=
                kvist_repl.worker_managed_allocation_inventory(
                    &worker,
                )
            for allocation in allocations {
                owner_name :=
                    repl_debug_hex_encode(allocation.owner_name)
                _ = fmt.fprintf(
                    os.stdout,
                    "%s%d\t%d\t%d\t%d\t%d\t%d\t%s\n",
                    REPL_WORKER_PHYSICAL_ALLOCATION_MARKER,
                    allocation.allocation,
                    allocation.size,
                    allocation.alignment,
                    allocation.generation,
                    int(allocation.owner_kind),
                    allocation.owner_generation,
                    owner_name,
                )
                delete(owner_name)
                for retained_generation in
                    allocation.retained_result_generations {
                    _ = fmt.fprintf(
                        os.stdout,
                        "%s%d\t%d\n",
                        REPL_WORKER_PHYSICAL_RETAINED_OWNER_MARKER,
                        allocation.allocation,
                        retained_generation,
                    )
                }
                for owner in allocation.retained_binding_owners {
                    owner_name :=
                        repl_debug_hex_encode(owner.name)
                    _ = fmt.fprintf(
                        os.stdout,
                        "%s%d\t%d\t%s\n",
                        REPL_WORKER_PHYSICAL_RETAINED_BINDING_MARKER,
                        allocation.allocation,
                        owner.generation,
                        owner_name,
                    )
                    delete(owner_name)
                }
            }
            delete(allocations)
            transfers :=
                kvist_repl.worker_managed_transfer_history(
                    &worker,
                )
            for transfer in transfers {
                owner_from_name :=
                    repl_debug_hex_encode(
                        transfer.owner_from_name,
                    )
                owner_to_name :=
                    repl_debug_hex_encode(
                        transfer.owner_to_name,
                    )
                _ = fmt.fprintf(
                    os.stdout,
                    "%s%d\t%d\t%d\t%d\t%d\t%s\t%d\t%d\t%s\t%d\n",
                    REPL_WORKER_PHYSICAL_TRANSFER_MARKER,
                    transfer.sequence,
                    transfer.allocation,
                    transfer.generation,
                    int(transfer.owner_from_kind),
                    transfer.owner_from_generation,
                    owner_from_name,
                    int(transfer.owner_to_kind),
                    transfer.owner_to_generation,
                    owner_to_name,
                    int(transfer.action),
                )
                delete(owner_from_name)
                delete(owner_to_name)
            }
            delete(transfers)
            fmt.println(
                REPL_WORKER_PHYSICAL_ALLOCATIONS_END_MARKER,
            )
            _ = os.flush(os.stdout)
            delete(raw)
            continue
        }
        if line == "" {
            delete(raw)
            continue
        }

        if strings.has_prefix(
            line,
            kvist_repl.WORKER_INCREMENTAL_PROGRAM_PREFIX,
        ) {
            run_start := time.tick_now()
            message, executed := kvist_repl.worker_execute_incremental_program(
                &worker,
                line[len(kvist_repl.WORKER_INCREMENTAL_PROGRAM_PREFIX):],
            )
            run_ns := time.duration_nanoseconds(time.tick_since(run_start))
            if executed {
                _ = fmt.fprintf(
                    os.stdout,
                    "%sok\t0\t%d\n",
                    REPL_WORKER_MARKER,
                    run_ns,
                )
            } else {
                _ = fmt.fprintf(
                    os.stdout,
                    "%serror\t%s\n",
                    REPL_WORKER_MARKER,
                    message,
                )
            }
            delete(message)
            _ = os.flush(os.stdout)
            delete(raw)
            continue
        }

        if strings.has_prefix(line, REPL_WORKER_EXECUTION_PLAN_PREFIX) {
            run_start := time.tick_now()
            message, executed := kvist_repl.worker_execute_plan(
                &worker,
                line[len(REPL_WORKER_EXECUTION_PLAN_PREFIX):],
            )
            run_ns := time.duration_nanoseconds(time.tick_since(run_start))
            if executed {
                if worker.last_run_aborted {
                    fmt.println(REPL_WORKER_ABORTED_MARKER)
                }
                _ = fmt.fprintf(
                    os.stdout,
                    "%sok\t0\t%d\n",
                    REPL_WORKER_MARKER,
                    run_ns,
                )
            } else {
                _ = fmt.fprintf(
                    os.stdout,
                    "%serror\t%s\n",
                    REPL_WORKER_MARKER,
                    message,
                )
            }
            delete(message)
            _ = os.flush(os.stdout)
            delete(raw)
            continue
        }

        if strings.has_prefix(line, REPL_WORKER_DIRECT_SCALAR_PREFIX) {
            fields := strings.split(line, "\t", context.temp_allocator)
            invoked := false
            run_start := time.tick_now()
            if len(fields) >= 3 && len(fields) <= 7 {
                name, name_ok := repl_debug_hex_decode(fields[1])
                signature, signature_ok := repl_debug_hex_decode(fields[2])
                args: [4]kvist_repl.Scalar_Value
                owned_strings: [4]string
                args_ok := name_ok && signature_ok
                for field, index in fields[3:] {
                    if len(field) < 2 || field[1] != ':' {
                        args_ok = false
                        break
                    }
                    value := field[2:]
                    switch field[0] {
                    case 'b':
                        if value != "0" && value != "1" {
                            args_ok = false
                            break
                        }
                        args[index] = {kind = .Bool, int_value = 1 if value == "1" else 0}
                    case 'i':
                        parsed_value, parsed := strconv.parse_int(value)
                        if !parsed {
                            args_ok = false
                            break
                        }
                        args[index] = {kind = .Int, int_value = i64(parsed_value)}
                    case 'f':
                        parsed_value, parsed := strconv.parse_f64(value)
                        if !parsed {
                            args_ok = false
                            break
                        }
                        args[index] = {kind = .F64, float_value = parsed_value}
                    case 's':
                        decoded, decoded_ok := repl_debug_hex_decode(value)
                        if !decoded_ok {
                            args_ok = false
                            break
                        }
                        owned_strings[index] = decoded
                        args[index] = {
                            kind = .String,
                            string_data = raw_data(decoded),
                            string_length = len(decoded),
                        }
                    case 'r':
                        result_name, decoded_ok := repl_debug_hex_decode(value)
                        if !decoded_ok {
                            args_ok = false
                            break
                        }
                        result_address: rawptr
                        for slot in worker.result_slots {
                            if slot.name == result_name &&
                               strings.has_prefix(slot.signature, "value:Data") {
                                result_address = slot.address
                                break
                            }
                        }
                        delete(result_name)
                        if result_address == nil {
                            args_ok = false
                            break
                        }
                        args[index] = {
                            kind = .Data,
                            source_address = result_address,
                        }
                    case:
                        args_ok = false
                    }
                    if !args_ok {
                        break
                    }
                }
                if args_ok {
                    invoked = kvist_repl.worker_invoke_scalar(
                        &worker,
                        name,
                        signature,
                        args[:len(fields)-3],
                    )
                }
                for value in owned_strings {
                    delete(value)
                }
                delete(name)
                delete(signature)
            }
            run_ns := time.duration_nanoseconds(time.tick_since(run_start))
            if invoked {
                if worker.last_run_aborted {
                    fmt.println(REPL_WORKER_ABORTED_MARKER)
                }
                _ = fmt.fprintf(
                    os.stdout,
                    "%sok\t0\t%d\n",
                    REPL_WORKER_MARKER,
                    run_ns,
                )
            } else {
                _, _ = os.write_strings(
                    os.stdout,
                    REPL_WORKER_MARKER,
                    "error\tinvalid direct scalar invocation\n",
                )
            }
            _ = os.flush(os.stdout)
            delete(raw)
            continue
        }

        if strings.has_prefix(line, REPL_WORKER_DIRECT_INT_PREFIX) {
            fields := strings.split(line, "\t", context.temp_allocator)
            invoked := false
            run_start := time.tick_now()
            if len(fields) >= 3 && len(fields) <= 7 {
                name, name_ok := repl_debug_hex_decode(fields[1])
                signature, signature_ok := repl_debug_hex_decode(fields[2])
                args: [4]int
                args_ok := name_ok && signature_ok
                for field, index in fields[3:] {
                    value, parsed := strconv.parse_int(field)
                    if !parsed {
                        args_ok = false
                        break
                    }
                    args[index] = value
                }
                if args_ok {
                    invoked = kvist_repl.worker_invoke_int(
                        &worker,
                        name,
                        signature,
                        args[:len(fields)-3],
                    )
                }
                delete(name)
                delete(signature)
            }
            run_ns := time.duration_nanoseconds(time.tick_since(run_start))
            if invoked {
                if worker.last_run_aborted {
                    fmt.println(REPL_WORKER_ABORTED_MARKER)
                }
                _ = fmt.fprintf(
                    os.stdout,
                    "%sok\t0\t%d\n",
                    REPL_WORKER_MARKER,
                    run_ns,
                )
            } else {
                _, _ = os.write_strings(
                    os.stdout,
                    REPL_WORKER_MARKER,
                    "error\tinvalid direct int invocation\n",
                )
            }
            _ = os.flush(os.stdout)
            delete(raw)
            continue
        }

        if strings.has_prefix(line, REPL_WORKER_LOADED_NATIVE_PREFIX) {
            path, path_ok :=
                repl_debug_hex_decode(
                    line[len(REPL_WORKER_LOADED_NATIVE_PREFIX):],
                )
            run_ns: i64
            message := ""
            executed := false
            if path_ok {
                message, executed =
                    kvist_repl.worker_run_loaded(
                        &worker,
                        path,
                        &run_ns,
                    )
            } else {
                message = strings.clone(
                    "invalid loaded native generation path",
                )
            }
            delete(path)
            _ = os.flush(os.stderr)
            if executed {
                if worker.last_run_aborted {
                    fmt.println(REPL_WORKER_ABORTED_MARKER)
                }
                _ = fmt.fprintf(
                    os.stdout,
                    "%sok\t0\t%d\n",
                    REPL_WORKER_MARKER,
                    run_ns,
                )
            } else {
                _, _ = os.write_strings(
                    os.stdout,
                    REPL_WORKER_MARKER,
                    "error\t",
                    message,
                    "\n",
                )
            }
            delete(message)
            _ = os.flush(os.stdout)
            delete(raw)
            continue
        }

        load_ns, run_ns: i64
        message, loaded :=
            kvist_repl.worker_load_and_run(
                &worker,
                line,
                &load_ns,
                &run_ns,
            )
        _ = os.flush(os.stderr)
        if loaded {
            if worker.last_run_aborted {
                fmt.println(REPL_WORKER_ABORTED_MARKER)
            }
            _ = fmt.fprintf(
                os.stdout,
                "%sok\t%d\t%d\n",
                REPL_WORKER_MARKER,
                load_ns,
                run_ns,
            )
        } else {
            _, _ = os.write_strings(os.stdout, REPL_WORKER_MARKER, "error\t", message, "\n")
            delete(message)
        }
        _ = os.flush(os.stdout)
        delete(raw)
    }
}

repl_worker_capture_stderr :: proc(worker: ^Repl_Worker_Process) {
    if worker.stderr_file == nil {
        return
    }
    delete(worker.captured_stderr)
    worker.captured_stderr = ""
    size, size_err := os.file_size(worker.stderr_file)
    if size_err != nil || size <= worker.stderr_offset {
        return
    }
    byte_count := int(size-worker.stderr_offset)
    bytes := make([]byte, byte_count)
    read_count, _ := os.read_at(
        worker.stderr_file,
        bytes,
        worker.stderr_offset,
    )
    worker.stderr_offset += i64(read_count)
    if read_count > 0 {
        worker.captured_stderr =
            strings.clone(string(bytes[:read_count]))
    }
    delete(bytes)
}

repl_worker_take_stderr :: proc(worker: ^Repl_Worker_Process) -> string {
    captured := worker.captured_stderr
    worker.captured_stderr = ""
    return captured
}

repl_start_worker :: proc() -> (worker: Repl_Worker_Process, message: string, ok: bool) {
    child_input, parent_input, input_err := os.pipe()
    if input_err != nil {
        return worker, strings.clone("failed to create REPL worker input pipe"), false
    }
    parent_output, child_output, output_err := os.pipe()
    if output_err != nil {
        _ = os.close(child_input)
        _ = os.close(parent_input)
        return worker, strings.clone("failed to create REPL worker output pipe"), false
    }
    stderr_dir, stderr_dir_err :=
        os.make_directory_temp(
            "",
            "kvist-repl-worker-stderr-*",
            context.allocator,
        )
    if stderr_dir_err != nil {
        _ = os.close(child_input)
        _ = os.close(parent_input)
        _ = os.close(parent_output)
        _ = os.close(child_output)
        return worker, strings.clone("failed to create REPL worker stderr directory"), false
    }
    stderr_path, stderr_path_err :=
        os.join_path(
            {stderr_dir, "stderr.log"},
            context.allocator,
        )
    if stderr_path_err != nil {
        _ = os.close(child_input)
        _ = os.close(parent_input)
        _ = os.close(parent_output)
        _ = os.close(child_output)
        _ = os.remove_all(stderr_dir)
        delete(stderr_dir)
        return worker, strings.clone("failed to create REPL worker stderr path"), false
    }
    stderr_file, stderr_open_err :=
        os.open(
            stderr_path,
            {.Read, .Write, .Create},
            os.Permissions_Read_Write_All,
        )
    if stderr_open_err != nil {
        _ = os.close(child_input)
        _ = os.close(parent_input)
        _ = os.close(parent_output)
        _ = os.close(child_output)
        _ = os.remove_all(stderr_dir)
        delete(stderr_path)
        delete(stderr_dir)
        return worker, strings.clone("failed to open REPL worker stderr capture"), false
    }

    process, start_err := os.process_start(os.Process_Desc{
        command = {os.args[0], "__repl-worker"},
        stdin = child_input,
        stdout = child_output,
        stderr = stderr_file,
    })
    _ = os.close(child_input)
    _ = os.close(child_output)
    if start_err != nil {
        _ = os.close(parent_input)
        _ = os.close(parent_output)
        _ = os.close(stderr_file)
        _ = os.remove_all(stderr_dir)
        delete(stderr_path)
        delete(stderr_dir)
        return worker, strings.clone("failed to start REPL worker"), false
    }

    worker = Repl_Worker_Process{
        process = process,
        input = parent_input,
        output = parent_output,
        alive = true,
        stderr_file = stderr_file,
        stderr_dir = stderr_dir,
        stderr_path = stderr_path,
    }
    bufio.reader_init(&worker.reader, os.to_reader(parent_output))
    return worker, "", true
}

repl_worker_delete_stderr_capture :: proc(worker: ^Repl_Worker_Process) {
    delete(worker.captured_stderr)
    if worker.stderr_file != nil {
        _ = os.close(worker.stderr_file)
    }
    if worker.stderr_dir != "" {
        _ = os.remove_all(worker.stderr_dir)
    }
    delete(worker.stderr_path)
    delete(worker.stderr_dir)
}

repl_stop_worker :: proc(worker: ^Repl_Worker_Process) {
    if !worker.alive {
        bufio.reader_destroy(&worker.reader)
        if worker.input != nil {
            _ = os.close(worker.input)
        }
        if worker.output != nil {
            _ = os.close(worker.output)
        }
        repl_worker_delete_stderr_capture(worker)
        worker^ = {}
        return
    }

    _, _ = os.write_string(worker.input, "__quit__\n")
    _ = os.flush(worker.input)
    _ = os.close(worker.input)
    _, _ = os.process_wait(worker.process)
    bufio.reader_destroy(&worker.reader)
    _ = os.close(worker.output)
    repl_worker_delete_stderr_capture(worker)
    worker^ = {}
}

repl_ensure_worker :: proc(worker: ^Repl_Worker_Process) -> (message: string, ok: bool) {
    if worker.alive {
        return "", true
    }
    repl_stop_worker(worker)
    next, start_message, started := repl_start_worker()
    if !started {
        return start_message, false
    }
    worker^ = next
    return "", true
}

repl_resume_paused_worker :: proc(worker: ^Repl_Worker_Process) {
    _, _ = os.write_strings(worker.input, "__continue__\n")
    _ = os.flush(worker.input)
}

repl_worker_checkpoint_command :: proc(
    worker: ^Repl_Worker_Process,
    command,
    name: string,
) -> (count: int, message: string, ok: bool) {
    encoded_name := repl_debug_hex_encode(name)
    defer delete(encoded_name)
    _, write_err := os.write_strings(
        worker.input,
        command,
        "\t",
        encoded_name,
        "\n",
    )
    if write_err != nil {
        worker.alive = false
        return 0, strings.clone("failed to send checkpoint command"), false
    }
    _ = os.flush(worker.input)
    raw, read_ok := repl_read_line(&worker.reader)
    if !read_ok {
        worker.alive = false
        return 0, strings.clone("REPL worker exited during checkpoint operation"), false
    }
    defer delete(raw)
    line := repl_trim_line(raw)
    if !strings.has_prefix(line, REPL_WORKER_CHECKPOINT_MARKER) {
        return 0,
               fmt.aprintf("unexpected checkpoint worker response: %q", line),
               false
    }
    fields := strings.split(
        line[len(REPL_WORKER_CHECKPOINT_MARKER):],
        "\t",
        context.temp_allocator,
    )
    if len(fields) != 3 {
        return 0, strings.clone("invalid checkpoint worker response"), false
    }
    parsed_count, count_ok := strconv.parse_int(fields[1])
    decoded_message := ""
    message_ok := fields[2] == "-"
    if !message_ok {
        decoded_message, message_ok = repl_debug_hex_decode(fields[2])
    }
    if !count_ok || !message_ok {
        if decoded_message != "" {
            delete(decoded_message)
        }
        return 0, strings.clone("invalid checkpoint worker response"), false
    }
    if fields[0] != "ok" {
        if decoded_message == "" {
            decoded_message = strings.clone("checkpoint operation failed")
        }
        return parsed_count, decoded_message, false
    }
    if decoded_message != "" {
        delete(decoded_message)
    }
    return parsed_count, "", true
}

repl_worker_checkpoints :: proc(
    worker: ^Repl_Worker_Process,
) -> (checkpoints: [dynamic]Repl_Checkpoint, message: string, ok: bool) {
    _, write_err := os.write_strings(worker.input, "__checkpoints__\n")
    if write_err != nil {
        worker.alive = false
        return checkpoints,
               strings.clone("failed to request checkpoint inventory"),
               false
    }
    _ = os.flush(worker.input)
    for {
        raw, read_ok := repl_read_line(&worker.reader)
        if !read_ok {
            worker.alive = false
            return checkpoints,
                   strings.clone(
                       "REPL worker exited during checkpoint inventory",
                   ),
                   false
        }
        line := repl_trim_line(raw)
        if line == REPL_WORKER_CHECKPOINTS_END_MARKER {
            delete(raw)
            return checkpoints, "", true
        }
        if !strings.has_prefix(line, REPL_WORKER_CHECKPOINT_ITEM_MARKER) {
            message = fmt.aprintf(
                "unexpected checkpoint inventory response: %q",
                line,
            )
            delete(raw)
            return checkpoints, message, false
        }
        fields := strings.split(
            line[len(REPL_WORKER_CHECKPOINT_ITEM_MARKER):],
            "\t",
            context.temp_allocator,
        )
        name := ""
        count := 0
        item_ok := len(fields) == 2
        if item_ok {
            name, item_ok = repl_debug_hex_decode(fields[0])
        }
        if item_ok {
            count, item_ok = strconv.parse_int(fields[1])
        }
        delete(raw)
        if !item_ok {
            if name != "" {
                delete(name)
            }
            return checkpoints,
                   strings.clone("invalid checkpoint inventory response"),
                   false
        }
        append(&checkpoints, Repl_Checkpoint{
            name = name,
            bindings = count,
        })
    }
}

repl_checkpoint_slice_delete :: proc(
    checkpoints: ^[dynamic]Repl_Checkpoint,
) {
    for checkpoint in checkpoints {
        delete(checkpoint.name)
    }
    delete(checkpoints^)
    checkpoints^ = nil
}

repl_worker_allocation_stats :: proc(
    worker: ^Repl_Worker_Process,
) -> (
    stats: kvist_repl.Worker_Allocation_Stats,
    message: string,
    ok: bool,
) {
    _, write_err :=
        os.write_string(worker.input, "__allocation_stats__\n")
    if write_err != nil {
        worker.alive = false
        return stats,
               strings.clone("failed to request runtime allocation stats"),
               false
    }
    _ = os.flush(worker.input)
    raw, read_ok := repl_read_line(&worker.reader)
    if !read_ok {
        worker.alive = false
        return stats,
               strings.clone(
                   "REPL worker exited during allocation stats",
               ),
               false
    }
    defer delete(raw)
    line := repl_trim_line(raw)
    if !strings.has_prefix(
        line,
        REPL_WORKER_ALLOCATION_STATS_MARKER,
    ) {
        return stats,
               fmt.aprintf(
                   "unexpected allocation stats response: %q",
                   line,
               ),
               false
    }
    fields := strings.split(
        line[len(REPL_WORKER_ALLOCATION_STATS_MARKER):],
        "\t",
        context.temp_allocator,
    )
    if len(fields) != 13 {
        return stats,
               strings.clone("invalid allocation stats response"),
               false
    }
    values: [13]int
    for field, index in fields {
        parsed := false
        values[index], parsed = strconv.parse_int(field)
        if !parsed {
            return stats,
                   strings.clone("invalid allocation stats response"),
                   false
        }
    }
    stats = kvist_repl.Worker_Allocation_Stats{
        live_allocations = values[0],
        live_bytes = values[1],
        total_allocations = values[2],
        total_allocated_bytes = values[3],
        total_frees = values[4],
        total_freed_bytes = values[5],
        managed_live_allocations = values[6],
        managed_live_bytes = values[7],
        managed_peak_bytes = values[8],
        managed_total_allocations = values[9],
        managed_total_allocated_bytes = values[10],
        managed_total_frees = values[11],
        managed_total_freed_bytes = values[12],
    }
    return stats, "", true
}

repl_physical_allocation_slice_delete :: proc(
    allocations: ^[dynamic]Repl_Physical_Allocation,
) {
    for allocation in allocations {
        delete(allocation.allocation_id)
        delete(allocation.owner_id)
        delete(allocation.kind)
        for owner_id in allocation.retained_owner_chain {
            delete(owner_id)
        }
        delete(allocation.retained_owner_chain)
    }
    delete(allocations^)
    allocations^ = nil
}

repl_physical_transfer_slice_delete :: proc(
    transfers: ^[dynamic]Repl_Physical_Transfer,
) {
    for transfer in transfers {
        delete(transfer.allocation_id)
        delete(transfer.owner_from)
        delete(transfer.owner_to)
        delete(transfer.action)
        delete(transfer.reason)
    }
    delete(transfers^)
    transfers^ = nil
}

repl_physical_owner_id :: proc(
    kind,
    generation: int,
    name := "",
) -> string {
    if kind ==
        int(kvist_repl.Worker_Managed_Owner_Kind.Binding) {
        return fmt.aprintf(
            "binding:%s:g%d",
            name,
            generation,
        )
    }
    if kind ==
        int(kvist_repl.Worker_Managed_Owner_Kind.Result) {
        return fmt.aprintf("result:g%d", generation)
    }
    return fmt.aprintf("generation:%d", generation)
}

repl_worker_physical_allocations :: proc(
    worker: ^Repl_Worker_Process,
) -> (
    allocations: [dynamic]Repl_Physical_Allocation,
    transfers: [dynamic]Repl_Physical_Transfer,
    message: string,
    ok: bool,
) {
    _, write_err :=
        os.write_string(worker.input, "__physical_allocations__\n")
    if write_err != nil {
        worker.alive = false
        return allocations, transfers,
               strings.clone(
                   "failed to request physical allocation inventory",
               ),
               false
    }
    _ = os.flush(worker.input)
    for {
        raw, read_ok := repl_read_line(&worker.reader)
        if !read_ok {
            worker.alive = false
            repl_physical_allocation_slice_delete(&allocations)
            repl_physical_transfer_slice_delete(&transfers)
            return allocations, transfers,
                   strings.clone(
                       "REPL worker exited during physical allocation inventory",
                   ),
                   false
        }
        line := repl_trim_line(raw)
        if line == REPL_WORKER_PHYSICAL_ALLOCATIONS_END_MARKER {
            delete(raw)
            return allocations, transfers, "", true
        }
        if strings.has_prefix(
            line,
            REPL_WORKER_PHYSICAL_TRANSFER_MARKER,
        ) {
            fields := strings.split(
                line[len(REPL_WORKER_PHYSICAL_TRANSFER_MARKER):],
                "\t",
                context.temp_allocator,
            )
            values: [8]int
            integer_fields := [8]int{0, 1, 2, 3, 4, 6, 7, 9}
            item_ok := len(fields) == 10
            if item_ok {
                for field_index, value_index in integer_fields {
                    values[value_index], item_ok =
                        strconv.parse_int(fields[field_index])
                    if !item_ok do break
                }
            }
            owner_from_name, from_name_ok := "", false
            owner_to_name, to_name_ok := "", false
            if item_ok {
                owner_from_name, from_name_ok =
                    repl_debug_hex_decode(fields[5])
                owner_to_name, to_name_ok =
                    repl_debug_hex_decode(fields[8])
                item_ok = from_name_ok && to_name_ok
            }
            defer delete(owner_from_name)
            defer delete(owner_to_name)
            delete(raw)
            if !item_ok {
                repl_physical_allocation_slice_delete(&allocations)
                repl_physical_transfer_slice_delete(&transfers)
                return allocations, transfers,
                       strings.clone(
                           "invalid physical transfer response",
                       ),
                       false
            }
            retained :=
                values[7] ==
                int(kvist_repl.Worker_Managed_Transfer_Action.Retained)
            action := "retained" if retained else "transferred"
            reason := "shared Data result retained" if retained else
                "exclusive result allocation transferred"
            if values[5] ==
               int(kvist_repl.Worker_Managed_Owner_Kind.Binding) {
                reason = "shared binding allocation retained" if
                    retained else
                    "exclusive binding allocation transferred"
            }
            append(&transfers, Repl_Physical_Transfer{
                sequence = values[0],
                allocation_id =
                    fmt.aprintf("managed:%d", values[1]),
                generation = values[2],
                owner_from =
                    repl_physical_owner_id(
                        values[3],
                        values[4],
                        owner_from_name,
                    ),
                owner_to =
                    repl_physical_owner_id(
                        values[5],
                        values[6],
                        owner_to_name,
                    ),
                action = strings.clone(action),
                reason = strings.clone(reason),
            })
            continue
        }
        if strings.has_prefix(
            line,
            REPL_WORKER_PHYSICAL_RETAINED_BINDING_MARKER,
        ) {
            fields := strings.split(
                line[len(REPL_WORKER_PHYSICAL_RETAINED_BINDING_MARKER):],
                "\t",
                context.temp_allocator,
            )
            allocation_id, allocation_ok := 0, false
            retained_generation, generation_ok := 0, false
            owner_name, name_ok := "", false
            if len(fields) == 3 {
                allocation_id, allocation_ok =
                    strconv.parse_int(fields[0])
                retained_generation, generation_ok =
                    strconv.parse_int(fields[1])
                owner_name, name_ok =
                    repl_debug_hex_decode(fields[2])
            }
            delete(raw)
            expected_id := -1
            if len(allocations) > 0 {
                expected_id_text :=
                    allocations[len(allocations)-1].allocation_id[
                        len("managed:"):
                    ]
                expected_id, _ =
                    strconv.parse_int(expected_id_text)
            }
            if !allocation_ok || !generation_ok ||
               !name_ok || allocation_id != expected_id {
                delete(owner_name)
                repl_physical_allocation_slice_delete(&allocations)
                repl_physical_transfer_slice_delete(&transfers)
                return allocations, transfers,
                       strings.clone(
                           "invalid physical retained binding response",
                       ),
                       false
            }
            owner_id := fmt.aprintf(
                "binding:%s:g%d",
                owner_name,
                retained_generation,
            )
            delete(owner_name)
            append(
                &allocations[len(allocations)-1].
                    retained_owner_chain,
                owner_id,
            )
            continue
        }
        if strings.has_prefix(
            line,
            REPL_WORKER_PHYSICAL_RETAINED_OWNER_MARKER,
        ) {
            fields := strings.split(
                line[len(REPL_WORKER_PHYSICAL_RETAINED_OWNER_MARKER):],
                "\t",
                context.temp_allocator,
            )
            allocation_id, allocation_ok := 0, false
            retained_generation, generation_ok := 0, false
            if len(fields) == 2 {
                allocation_id, allocation_ok =
                    strconv.parse_int(fields[0])
                retained_generation, generation_ok =
                    strconv.parse_int(fields[1])
            }
            delete(raw)
            expected_id := -1
            if len(allocations) > 0 {
                expected_id_text :=
                    allocations[len(allocations)-1].allocation_id[
                        len("managed:"):
                    ]
                expected_id, _ =
                    strconv.parse_int(expected_id_text)
            }
            if !allocation_ok || !generation_ok ||
               allocation_id != expected_id {
                repl_physical_allocation_slice_delete(&allocations)
                repl_physical_transfer_slice_delete(&transfers)
                return allocations, transfers,
                       strings.clone(
                           "invalid physical retained owner response",
                       ),
                       false
            }
            owner_id :=
                fmt.aprintf("result:g%d", retained_generation)
            append(
                &allocations[len(allocations)-1].
                    retained_owner_chain,
                owner_id,
            )
            continue
        }
        if !strings.has_prefix(
            line,
            REPL_WORKER_PHYSICAL_ALLOCATION_MARKER,
        ) {
            message = fmt.aprintf(
                "unexpected physical allocation response: %q",
                line,
            )
            delete(raw)
            repl_physical_allocation_slice_delete(&allocations)
            repl_physical_transfer_slice_delete(&transfers)
            return allocations, transfers, message, false
        }
        fields := strings.split(
            line[len(REPL_WORKER_PHYSICAL_ALLOCATION_MARKER):],
            "\t",
            context.temp_allocator,
        )
        values: [6]int
        item_ok := len(fields) == 7
        if item_ok {
            for index in 0..<len(values) {
                values[index], item_ok =
                    strconv.parse_int(fields[index])
                if !item_ok do break
            }
        }
        owner_name, name_ok := "", false
        if item_ok {
            owner_name, name_ok =
                repl_debug_hex_decode(fields[6])
            item_ok = name_ok
        }
        delete(raw)
        if !item_ok {
            repl_physical_allocation_slice_delete(&allocations)
            repl_physical_transfer_slice_delete(&transfers)
            return allocations, transfers,
                   strings.clone(
                       "invalid physical allocation response",
                   ),
                   false
        }
        owner_id :=
            repl_physical_owner_id(
                values[4],
                values[5],
                owner_name,
            )
        delete(owner_name)
        owner_chain := make([dynamic]string, 0, 2)
        append(&owner_chain, strings.clone(owner_id))
        append(&allocations, Repl_Physical_Allocation{
            allocation_id =
                fmt.aprintf("managed:%d", values[0]),
            owner_id = owner_id,
            kind = strings.clone("managed"),
            size = values[1],
            alignment = values[2],
            generation = values[3],
            retained_owner_chain = owner_chain,
        })
    }
}

repl_restart_paused_worker :: proc(
    worker: ^Repl_Worker_Process,
    name,
    value: string,
) {
    encoded_name := repl_debug_hex_encode(name)
    defer delete(encoded_name)
    encoded_value := "-"
    owned_encoded_value := ""
    if value != "" {
        owned_encoded_value = repl_debug_hex_encode(value)
        encoded_value = owned_encoded_value
    }
    defer delete(owned_encoded_value)
    _, _ = os.write_strings(
        worker.input,
        "__restart__\t",
        encoded_name,
        "\t",
        encoded_value,
        "\n",
    )
    _ = os.flush(worker.input)
}

repl_step_paused_worker :: proc(
    worker: ^Repl_Worker_Process,
    command: string,
) {
    _, _ = os.write_strings(worker.input, command, "\n")
    _ = os.flush(worker.input)
}

repl_abort_paused_worker :: proc(worker: ^Repl_Worker_Process) {
    _, _ = os.write_strings(worker.input, "__abort__\n")
    _ = os.flush(worker.input)
}

repl_session_debug_frame :: proc(
    session: ^Repl_Session,
    pause_id: string,
) -> (^Repl_Debug_Frame, bool) {
    for &generation in session.generations {
        for &frame in generation.pause_points {
            if frame.pause_id == pause_id {
                return &frame, true
            }
        }
    }
    return nil, false
}

repl_trace_frame :: proc(
    session: ^Repl_Session,
    pending_frames: []Repl_Debug_Frame,
    trace_id: string,
) -> (^Repl_Debug_Frame, bool) {
    for &frame in pending_frames {
        if frame.pause_id == trace_id {
            return &frame, true
        }
    }
    if session != nil {
        return repl_session_debug_frame(session, trace_id)
    }
    return nil, false
}

repl_trace_sample_delete :: proc(sample: ^Repl_Trace_Sample) {
    delete(sample.source_path)
    delete(sample.trace_id)
    sample^ = {}
}

repl_trace_sample_set :: proc(
    sample: ^Repl_Trace_Sample,
    frame: ^Repl_Debug_Frame,
    frame_ok: bool,
    trace_id: string,
    elapsed_ns: int,
) {
    repl_trace_sample_delete(sample)
    if frame_ok {
        sample.source_path = strings.clone(frame.source_path)
        sample.line = frame.line
        sample.column = frame.column
    }
    sample.trace_id = strings.clone(trace_id)
    sample.elapsed_ns = elapsed_ns
}

repl_trace_add_interval :: proc(
    hotspots: ^[dynamic]Repl_Trace_Hotspot,
    sample: Repl_Trace_Sample,
    interval_ns: int,
) {
    duration_ns := max(interval_ns, 0)
    for &hotspot in hotspots {
        if hotspot.trace_id == sample.trace_id {
            hotspot.hits += 1
            hotspot.total_ns += duration_ns
            hotspot.max_ns = max(hotspot.max_ns, duration_ns)
            return
        }
    }
    append(hotspots, Repl_Trace_Hotspot{
        source_path = strings.clone(sample.source_path),
        line = Repl_Optional_Int(sample.line) if sample.line > 0 else {},
        column = Repl_Optional_Int(sample.column) if sample.column > 0 else {},
        trace_id = strings.clone(sample.trace_id),
        hits = 1,
        total_ns = duration_ns,
        max_ns = duration_ns,
    })
}

repl_trace_hotspots_sort :: proc(hotspots: ^[dynamic]Repl_Trace_Hotspot) {
    sort.sort(sort.Interface{
        collection = rawptr(hotspots),
        len = proc(interface: sort.Interface) -> int {
            values :=
                (^([dynamic]Repl_Trace_Hotspot))(interface.collection)
            return len(values^)
        },
        less = proc(interface: sort.Interface, i, j: int) -> bool {
            values :=
                (^([dynamic]Repl_Trace_Hotspot))(interface.collection)
            if values[i].total_ns != values[j].total_ns {
                return values[i].total_ns > values[j].total_ns
            }
            return values[i].trace_id < values[j].trace_id
        },
        swap = proc(interface: sort.Interface, i, j: int) {
            values :=
                (^([dynamic]Repl_Trace_Hotspot))(interface.collection)
            values[i], values[j] = values[j], values[i]
        },
    })
}

repl_trace_hotspots_delete :: proc(
    hotspots: ^[dynamic]Repl_Trace_Hotspot,
) {
    for &hotspot in hotspots {
        delete(hotspot.source_path)
        delete(hotspot.trace_id)
    }
    delete(hotspots^)
}

repl_debug_frame_clone :: proc(source: Repl_Debug_Frame) -> Repl_Debug_Frame {
    frame := Repl_Debug_Frame{
        frame_id = strings.clone(source.frame_id),
        pause_id = strings.clone(source.pause_id),
        generation = source.generation,
        definition_name = strings.clone(source.definition_name),
        definition_version = source.definition_version,
        source_path = strings.clone(source.source_path),
        line = source.line,
        column = source.column,
        phase = strings.clone(source.phase),
    }
    for local in source.locals {
        append(&frame.locals, repl_debug_local_clone(local))
    }
    for collection in source.collections {
        append(&frame.collections, Repl_Debug_Collection{
            path = strings.clone(collection.path),
            shape = strings.clone(collection.shape),
            element_type = strings.clone(collection.element_type),
            key_type = strings.clone(collection.key_type),
            value_type = strings.clone(collection.value_type),
            descriptor = collection.descriptor,
        })
    }
    return frame
}

repl_debug_frame_delete :: proc(frame: ^Repl_Debug_Frame) {
    delete(frame.frame_id)
    delete(frame.pause_id)
    delete(frame.definition_name)
    delete(frame.source_path)
    delete(frame.phase)
    for &local in frame.locals {
        repl_debug_local_delete(&local)
    }
    delete(frame.locals)
    for &collection in frame.collections {
        delete(collection.path)
        delete(collection.shape)
        delete(collection.element_type)
        delete(collection.key_type)
        delete(collection.value_type)
    }
    delete(frame.collections)
    frame^ = {}
}

repl_debug_collections_delete :: proc(
    collections: []Repl_Debug_Collection,
) {
    for &collection in collections {
        delete(collection.path)
        delete(collection.shape)
        delete(collection.element_type)
        delete(collection.key_type)
        delete(collection.value_type)
    }
    delete(collections)
}

Repl_Debug_Eval_Kind :: enum {
    Invalid,
    Int,
    Bool,
}

Repl_Debug_Eval_Value :: struct {
    kind:       Repl_Debug_Eval_Kind,
    int_value:  int,
    bool_value: bool,
}

repl_debug_snapshot_lookup :: proc(
    frame: ^Repl_Debug_Frame,
    source_path: string,
) -> (ty, value: string, found: bool) {
    dot := strings.index(source_path, ".")
    bracket := strings.index(source_path, "[")
    separator := dot
    separator_is_bracket := false
    if bracket >= 0 && (separator < 0 || bracket < separator) {
        separator = bracket
        separator_is_bracket = true
    }
    root_source := source_path
    member_source := ""
    if separator >= 0 {
        path_start := separator if separator_is_bracket else separator+1
        if separator == 0 || path_start >= len(source_path) {
            return "", "", false
        }
        root_source = source_path[:separator]
        member_source = source_path[path_start:]
    }
    root := kvist.map_name(root_source)
    defer delete(root)
    for local in frame.locals {
        if local.name != root {
            continue
        }
        if member_source == "" {
            return local.ty, local.value, true
        }
        mapped_member := kvist.map_name(member_source)
        defer delete(mapped_member)
        for path in local.paths {
            if path.path == member_source ||
               path.path == mapped_member {
                return path.ty, path.value, true
            }
        }
        return "", "", false
    }
    return "", "", false
}

repl_debug_eval_local :: proc(
    frame: ^Repl_Debug_Frame,
    source_name: string,
) -> (Repl_Debug_Eval_Value, string, bool) {
    ty, snapshot, found :=
        repl_debug_snapshot_lookup(frame, source_name)
    if found {
        if snapshot == "<moved>" || snapshot == "<unavailable>" {
            return {}, fmt.tprintf(
                "local %s is %s at the active safe point",
                source_name,
                snapshot,
            ), false
        }
        if ty == "int" {
            parsed, ok := strconv.parse_int(snapshot)
            if !ok {
                return {}, fmt.tprintf(
                    "local %s has a malformed int snapshot",
                    source_name,
                ), false
            }
            return Repl_Debug_Eval_Value{
                kind = .Int,
                int_value = parsed,
            }, "", true
        }
        if ty == "bool" {
            if snapshot == "true" {
                return Repl_Debug_Eval_Value{
                    kind = .Bool,
                    bool_value = true,
                }, "", true
            }
            if snapshot == "false" {
                return Repl_Debug_Eval_Value{
                    kind = .Bool,
                }, "", true
            }
            return {}, fmt.tprintf(
                "local %s has a malformed bool snapshot",
                source_name,
            ), false
        }
        return {}, fmt.tprintf(
            "compound paused evaluation supports int and bool locals; %s has type %s",
            source_name,
            ty,
        ), false
    }
    return {}, fmt.tprintf(
        "local is not visible in the active frame: %s",
        source_name,
    ), false
}

repl_debug_eval_expect_kind :: proc(
    value: Repl_Debug_Eval_Value,
    expected: Repl_Debug_Eval_Kind,
    operator: string,
) -> (string, bool) {
    if value.kind == expected {
        return "", true
    }
    expected_name := "int"
    if expected == .Bool {
        expected_name = "bool"
    }
    return fmt.tprintf(
        "%s expects %s operands in paused evaluation",
        operator,
        expected_name,
    ), false
}

repl_debug_eval_snapshot_path :: proc(
    form: kvist.CST_Form,
) -> (string, string, bool) {
    // Returned paths intentionally use session-lifetime allocation. Paused
    // evaluation is allowed to accumulate this small debugger metadata, and
    // releasing it between requests can invalidate reader-temporary storage.
    if form.kind == .Symbol {
        return strings.clone(form.text), "", true
    }
    if form.kind != .List || len(form.items) != 3 ||
       form.items[0].kind != .Symbol {
        return "", "paused array access requires a captured path", false
    }
    operator := form.items[0].text
    if operator == "__kvist_field" {
        base, base_message, base_ok :=
            repl_debug_eval_snapshot_path(form.items[1])
        if !base_ok {
            return "", base_message, false
        }
        field := form.items[2]
        if field.kind != .Symbol {
            return "", "paused field access requires a literal field name", false
        }
        return strings.clone(
            fmt.tprintf("%s.%s", base, field.text),
        ), "", true
    }
    if operator != "__kvist_index" {
        return "", "paused aggregate access requires a captured path", false
    }
    base, base_message, base_ok :=
        repl_debug_eval_snapshot_path(form.items[1])
    if !base_ok {
        return "", base_message, false
    }
    key_form := form.items[2]
    if key_form.kind == .String || key_form.kind == .Bool {
        return strings.clone(
            fmt.tprintf("%s[%s]", base, key_form.text),
        ), "", true
    }
    if key_form.kind != .Number {
        return "", "paused aggregate access requires a literal index or map key", false
    }
    negative := strings.has_prefix(key_form.text, "-")
    digits_start := 1 if negative else 0
    if digits_start == len(key_form.text) {
        return "", "paused aggregate access requires an integer index", false
    }
    for byte, index in transmute([]byte)key_form.text {
        if index == 0 && byte == '-' {
            continue
        }
        if byte < '0' || byte > '9' {
            return "", "paused aggregate access requires an integer index", false
        }
    }
    normalized_start := digits_start
    for normalized_start+1 < len(key_form.text) &&
        key_form.text[normalized_start] == '0' {
        normalized_start += 1
    }
    normalized_digits := key_form.text[normalized_start:]
    normalized := normalized_digits
    if negative && normalized_digits != "0" {
        normalized = fmt.tprintf("-%s", normalized_digits)
    }
    return strings.clone(
        fmt.tprintf("%s[%s]", base, normalized),
    ), "", true
}

repl_debug_eval_infer_kind :: proc(
    frame: ^Repl_Debug_Frame,
    form: kvist.CST_Form,
) -> (Repl_Debug_Eval_Kind, string, bool) {
    #partial switch form.kind {
    case .Number:
        for byte in transmute([]byte)form.text {
            if byte == '.' || byte == 'e' || byte == 'E' {
                return .Invalid, "paused evaluation currently supports integer literals only", false
            }
        }
        return .Int, "", true
    case .Bool:
        return .Bool, "", true
    case .Symbol:
        ty, _, found := repl_debug_snapshot_lookup(frame, form.text)
        if found {
            if ty == "int" {
                return .Int, "", true
            }
            if ty == "bool" {
                return .Bool, "", true
            }
            return .Invalid, fmt.tprintf(
                "compound paused evaluation supports int and bool locals; %s has type %s",
                form.text,
                ty,
            ), false
        }
        return .Invalid, fmt.tprintf(
            "local is not visible in the active frame: %s",
            form.text,
        ), false
    case .List:
        if len(form.items) == 0 ||
           form.items[0].kind != .Symbol {
            return .Invalid, "paused evaluation requires an operator-headed form", false
        }
        operator := form.items[0].text
        operands := form.items[1:]
        if operator == "__kvist_index" ||
           operator == "__kvist_field" {
            path, path_message, path_ok :=
                repl_debug_eval_snapshot_path(form)
            if !path_ok {
                return .Invalid, path_message, false
            }
            ty, _, found := repl_debug_snapshot_lookup(frame, path)
            if !found {
                return .Invalid, fmt.tprintf(
                    "aggregate path is not captured in the active frame: %s",
                    path,
                ), false
            }
            if ty == "int" {
                return .Int, "", true
            }
            if ty == "bool" {
                return .Bool, "", true
            }
            return .Invalid, fmt.tprintf(
                "compound paused evaluation supports int and bool paths; %s has type %s",
                path,
                ty,
            ), false
        }
        expected := Repl_Debug_Eval_Kind.Int
        result := Repl_Debug_Eval_Kind.Int
        if operator == "not" || operator == "!" ||
           operator == "and" || operator == "or" {
            expected = .Bool
            result = .Bool
        } else if operator == "=" || operator == "==" ||
                  operator == "!=" {
            if len(operands) < 2 {
                return .Invalid, fmt.tprintf(
                    "%s expects at least two arguments",
                    operator,
                ), false
            }
            first_kind, message, ok :=
                repl_debug_eval_infer_kind(frame, operands[0])
            if !ok {
                return .Invalid, message, false
            }
            for operand in operands[1:] {
                kind, operand_message, operand_ok :=
                    repl_debug_eval_infer_kind(frame, operand)
                if !operand_ok {
                    return .Invalid, operand_message, false
                }
                if kind != first_kind {
                    return .Invalid, fmt.tprintf(
                        "%s operands must have the same type",
                        operator,
                    ), false
                }
            }
            return .Bool, "", true
        } else if operator == "<" || operator == "<=" ||
                  operator == ">" || operator == ">=" {
            result = .Bool
        } else if operator == "if" {
            if len(operands) != 3 {
                return .Invalid, "if expects test, then, and else in paused evaluation", false
            }
            test_kind, test_message, test_ok :=
                repl_debug_eval_infer_kind(frame, operands[0])
            if !test_ok {
                return .Invalid, test_message, false
            }
            if test_kind != .Bool {
                return .Invalid, "if expects a bool test in paused evaluation", false
            }
            then_kind, then_message, then_ok :=
                repl_debug_eval_infer_kind(frame, operands[1])
            if !then_ok {
                return .Invalid, then_message, false
            }
            else_kind, else_message, else_ok :=
                repl_debug_eval_infer_kind(frame, operands[2])
            if !else_ok {
                return .Invalid, else_message, false
            }
            if then_kind != else_kind {
                return .Invalid, "paused if branches must have the same type", false
            }
            return then_kind, "", true
        } else if operator != "+" && operator != "-" &&
                  operator != "*" && operator != "/" &&
                  operator != "%" && operator != "min" &&
                  operator != "max" {
            return .Invalid, fmt.tprintf(
                "unsupported operator in paused evaluation: %s",
                operator,
            ), false
        }
        for operand in operands {
            kind, message, ok :=
                repl_debug_eval_infer_kind(frame, operand)
            if !ok {
                return .Invalid, message, false
            }
            if kind != expected {
                expected_name := "int"
                if expected == .Bool {
                    expected_name = "bool"
                }
                return .Invalid, fmt.tprintf(
                    "%s expects %s operands in paused evaluation",
                    operator,
                    expected_name,
                ), false
            }
        }
        return result, "", true
    case:
        return .Invalid, "paused evaluation supports int/bool literals, locals, and pure scalar forms", false
    }
}

repl_debug_checked_add :: proc(a, b: int) -> (int, bool) {
    if (b > 0 && a > max(int)-b) ||
       (b < 0 && a < min(int)-b) {
        return 0, false
    }
    return a+b, true
}

repl_debug_checked_sub :: proc(a, b: int) -> (int, bool) {
    if (b > 0 && a < min(int)+b) ||
       (b < 0 && a > max(int)+b) {
        return 0, false
    }
    return a-b, true
}

repl_debug_checked_mul :: proc(a, b: int) -> (int, bool) {
    if a == 0 || b == 0 {
        return 0, true
    }
    if (a == min(int) && b == -1) ||
       (b == min(int) && a == -1) {
        return 0, false
    }
    if a > 0 {
        if (b > 0 && a > max(int)/b) ||
           (b < 0 && b < min(int)/a) {
            return 0, false
        }
    } else {
        if (b > 0 && a < min(int)/b) ||
           (b < 0 && a < max(int)/b) {
            return 0, false
        }
    }
    return a*b, true
}

repl_debug_eval_form :: proc(
    frame: ^Repl_Debug_Frame,
    form: kvist.CST_Form,
) -> (Repl_Debug_Eval_Value, string, bool) {
    #partial switch form.kind {
    case .Number:
        for byte in transmute([]byte)form.text {
            if byte == '.' || byte == 'e' || byte == 'E' {
                return {}, "paused evaluation currently supports integer literals only", false
            }
        }
        parsed, ok := strconv.parse_int(form.text)
        if !ok {
            return {}, "invalid integer literal in paused evaluation", false
        }
        return Repl_Debug_Eval_Value{
            kind = .Int,
            int_value = parsed,
        }, "", true
    case .Bool:
        return Repl_Debug_Eval_Value{
            kind = .Bool,
            bool_value = form.text == "true",
        }, "", true
    case .Symbol:
        return repl_debug_eval_local(frame, form.text)
    case .List:
        if len(form.items) == 0 ||
           form.items[0].kind != .Symbol {
            return {}, "paused evaluation requires an operator-headed form", false
        }
        operator := form.items[0].text
        operands := form.items[1:]
        if operator == "__kvist_index" ||
           operator == "__kvist_field" {
            path, path_message, path_ok :=
                repl_debug_eval_snapshot_path(form)
            if !path_ok {
                return {}, path_message, false
            }
            return repl_debug_eval_local(frame, path)
        }
        if operator == "not" || operator == "!" {
            if len(operands) != 1 {
                return {}, "not expects one argument", false
            }
            value, message, ok := repl_debug_eval_form(frame, operands[0])
            if !ok {
                return {}, message, false
            }
            if kind_message, kind_ok :=
                repl_debug_eval_expect_kind(value, .Bool, "not");
               !kind_ok {
                return {}, kind_message, false
            }
            return Repl_Debug_Eval_Value{
                kind = .Bool,
                bool_value = !value.bool_value,
            }, "", true
        }
        if operator == "and" || operator == "or" {
            if len(operands) < 2 {
                return {}, fmt.tprintf(
                    "%s expects at least two arguments",
                    operator,
                ), false
            }
            result := operator == "and"
            for operand in operands {
                value, message, ok :=
                    repl_debug_eval_form(frame, operand)
                if !ok {
                    return {}, message, false
                }
                if kind_message, kind_ok :=
                    repl_debug_eval_expect_kind(
                        value,
                        .Bool,
                        operator,
                    );
                   !kind_ok {
                    return {}, kind_message, false
                }
                if operator == "and" {
                    result = result && value.bool_value
                    if !result {
                        break
                    }
                } else {
                    result = result || value.bool_value
                    if result {
                        break
                    }
                }
            }
            return Repl_Debug_Eval_Value{
                kind = .Bool,
                bool_value = result,
            }, "", true
        }
        if operator == "if" {
            if len(operands) != 3 {
                return {}, "if expects test, then, and else in paused evaluation", false
            }
            test, message, ok :=
                repl_debug_eval_form(frame, operands[0])
            if !ok {
                return {}, message, false
            }
            if kind_message, kind_ok :=
                repl_debug_eval_expect_kind(test, .Bool, "if");
               !kind_ok {
                return {}, kind_message, false
            }
            if test.bool_value {
                return repl_debug_eval_form(frame, operands[1])
            }
            return repl_debug_eval_form(frame, operands[2])
        }
        if operator == "+" || operator == "-" ||
           operator == "*" || operator == "/" ||
           operator == "%" || operator == "min" ||
           operator == "max" {
            minimum := 2
            if operator == "-" {
                minimum = 1
            }
            if len(operands) < minimum {
                return {}, fmt.tprintf(
                    "%s expects at least %d argument%s",
                    operator,
                    minimum,
                    "" if minimum == 1 else "s",
                ), false
            }
            first, message, ok :=
                repl_debug_eval_form(frame, operands[0])
            if !ok {
                return {}, message, false
            }
            if kind_message, kind_ok :=
                repl_debug_eval_expect_kind(first, .Int, operator);
               !kind_ok {
                return {}, kind_message, false
            }
            result := first.int_value
            if operator == "-" && len(operands) == 1 {
                if result == min(int) {
                    return {}, "integer overflow in paused evaluation", false
                }
                result = -result
            }
            for operand in operands[1:] {
                value, operand_message, operand_ok :=
                    repl_debug_eval_form(frame, operand)
                if !operand_ok {
                    return {}, operand_message, false
                }
                if kind_message, kind_ok :=
                    repl_debug_eval_expect_kind(
                        value,
                        .Int,
                        operator,
                    );
                   !kind_ok {
                    return {}, kind_message, false
                }
                arithmetic_ok := true
                switch operator {
                case "+":
                    result, arithmetic_ok =
                        repl_debug_checked_add(result, value.int_value)
                case "-":
                    result, arithmetic_ok =
                        repl_debug_checked_sub(result, value.int_value)
                case "*":
                    result, arithmetic_ok =
                        repl_debug_checked_mul(result, value.int_value)
                case "/":
                    if value.int_value == 0 {
                        return {}, "division by zero in paused evaluation", false
                    }
                    if result == min(int) && value.int_value == -1 {
                        arithmetic_ok = false
                    } else {
                        result /= value.int_value
                    }
                case "%":
                    if value.int_value == 0 {
                        return {}, "modulo by zero in paused evaluation", false
                    }
                    if result == min(int) && value.int_value == -1 {
                        result = 0
                    } else {
                        result %= value.int_value
                    }
                case "min":
                    result = min(result, value.int_value)
                case "max":
                    result = max(result, value.int_value)
                }
                if !arithmetic_ok {
                    return {}, "integer overflow in paused evaluation", false
                }
            }
            return Repl_Debug_Eval_Value{
                kind = .Int,
                int_value = result,
            }, "", true
        }
        if operator == "=" || operator == "==" ||
           operator == "!=" || operator == "<" ||
           operator == "<=" || operator == ">" ||
           operator == ">=" {
            if len(operands) < 2 ||
               (operator == "!=" && len(operands) != 2) {
                return {}, fmt.tprintf(
                    "%s expects %s",
                    operator,
                    "exactly two arguments" if operator == "!=" else
                        "at least two arguments",
                ), false
            }
            values: [dynamic]Repl_Debug_Eval_Value
            defer delete(values)
            for operand in operands {
                value, message, ok :=
                    repl_debug_eval_form(frame, operand)
                if !ok {
                    return {}, message, false
                }
                append(&values, value)
            }
            result := true
            for i in 0 ..< len(values)-1 {
                left := values[i]
                right := values[i+1]
                if left.kind != right.kind {
                    return {}, fmt.tprintf(
                        "%s operands must have the same type",
                        operator,
                    ), false
                }
                pair := false
                if operator == "=" || operator == "==" ||
                   operator == "!=" {
                    if left.kind == .Int {
                        pair = left.int_value == right.int_value
                    } else if left.kind == .Bool {
                        pair = left.bool_value == right.bool_value
                    } else {
                        return {}, "unsupported equality operands in paused evaluation", false
                    }
                    if operator == "!=" {
                        pair = !pair
                    }
                } else {
                    if left.kind != .Int {
                        return {}, fmt.tprintf(
                            "%s expects int operands in paused evaluation",
                            operator,
                        ), false
                    }
                    switch operator {
                    case "<":  pair = left.int_value < right.int_value
                    case "<=": pair = left.int_value <= right.int_value
                    case ">":  pair = left.int_value > right.int_value
                    case ">=": pair = left.int_value >= right.int_value
                    }
                }
                result = result && pair
                if !result {
                    break
                }
            }
            return Repl_Debug_Eval_Value{
                kind = .Bool,
                bool_value = result,
            }, "", true
        }
        return {}, fmt.tprintf(
            "unsupported operator in paused evaluation: %s",
            operator,
        ), false
    case:
        return {}, "paused evaluation supports int/bool literals, locals, and pure scalar forms", false
    }
}

repl_debug_eval_render :: proc(
    value: Repl_Debug_Eval_Value,
) -> (text, ty: string, ok: bool) {
    switch value.kind {
    case .Int:
        return fmt.tprintf("%d", value.int_value), "int", true
    case .Bool:
        return "true" if value.bool_value else "false", "bool", true
    case .Invalid:
        return "", "", false
    }
    return "", "", false
}

repl_debug_page_worker :: proc(
    worker: ^Repl_Worker_Process,
    descriptor,
    offset,
    limit: int,
) -> (
    entries: [dynamic]Repl_Inspection_Entry,
    total: int,
    collections: [dynamic]Repl_Debug_Collection,
    ok: bool,
) {
    command := fmt.tprintf(
        "__debug_page__\t%d\t%d\t%d\n",
        descriptor,
        offset,
        limit,
    )
    // tprintf uses the temporary allocator; do not explicitly delete it.
    _, write_err := os.write_strings(
        worker.input,
        command,
    )
    if write_err != nil {
        worker.alive = false
        return entries, 0, collections, false
    }
    _ = os.flush(worker.input)
    for {
        raw, read_ok := repl_read_line(&worker.reader)
        if !read_ok {
            worker.alive = false
            repl_inspection_entries_delete(entries[:])
            repl_debug_collections_delete(collections[:])
            return nil, 0, nil, false
        }
        line := repl_trim_line(raw)
        if strings.has_prefix(
            line,
            REPL_WORKER_DEBUG_PAGE_ITEM_MARKER,
        ) {
            fields := strings.split(
                line[len(REPL_WORKER_DEBUG_PAGE_ITEM_MARKER):],
                "\t",
                context.allocator,
            )
            if len(fields) != 3 {
                delete(fields)
                delete(raw)
                repl_inspection_entries_delete(entries[:])
                repl_debug_collections_delete(collections[:])
                return nil, 0, nil, false
            }
            index, index_ok := strconv.parse_int(fields[0])
            key, key_ok := repl_debug_hex_decode(fields[1])
            value, value_ok := repl_debug_hex_decode(fields[2])
            delete(fields)
            delete(raw)
            if !index_ok || !key_ok || !value_ok {
                delete(key)
                delete(value)
                repl_inspection_entries_delete(entries[:])
                repl_debug_collections_delete(collections[:])
                return nil, 0, nil, false
            }
            append(&entries, Repl_Inspection_Entry{
                index = Repl_Optional_Int(index),
                key = key,
                value = value,
            })
            continue
        }
        if strings.has_prefix(
            line,
            REPL_WORKER_DEBUG_COLLECTION_MARKER,
        ) {
            fields := strings.split(
                line[len(REPL_WORKER_DEBUG_COLLECTION_MARKER):],
                "\t",
                context.allocator,
            )
            if len(fields) != 6 {
                delete(fields)
                delete(raw)
                repl_inspection_entries_delete(entries[:])
                repl_debug_collections_delete(collections[:])
                return nil, 0, nil, false
            }
            descriptor, descriptor_ok := strconv.parse_int(fields[0])
            path, path_ok := repl_debug_hex_decode(fields[1])
            shape, shape_ok := repl_debug_hex_decode(fields[2])
            element_type, element_type_ok :=
                repl_debug_hex_decode(fields[3])
            key_type, key_type_ok := repl_debug_hex_decode(fields[4])
            value_type, value_type_ok :=
                repl_debug_hex_decode(fields[5])
            delete(fields)
            delete(raw)
            if !descriptor_ok || descriptor < 0 ||
               !path_ok || !shape_ok || !element_type_ok ||
               !key_type_ok || !value_type_ok {
                delete(path)
                delete(shape)
                delete(element_type)
                delete(key_type)
                delete(value_type)
                repl_inspection_entries_delete(entries[:])
                repl_debug_collections_delete(collections[:])
                return nil, 0, nil, false
            }
            append(&collections, Repl_Debug_Collection{
                path = path,
                shape = shape,
                element_type = element_type,
                key_type = key_type,
                value_type = value_type,
                descriptor = descriptor,
            })
            continue
        }
        if strings.has_prefix(
            line,
            REPL_WORKER_DEBUG_PAGE_END_MARKER,
        ) {
            parsed_total, total_ok := strconv.parse_int(
                line[len(REPL_WORKER_DEBUG_PAGE_END_MARKER):],
            )
            delete(raw)
            if !total_ok || parsed_total < 0 {
                repl_inspection_entries_delete(entries[:])
                repl_debug_collections_delete(collections[:])
                return nil, 0, nil, false
            }
            return entries, parsed_total, collections, true
        }
        delete(raw)
        repl_inspection_entries_delete(entries[:])
        repl_debug_collections_delete(collections[:])
        return nil, 0, nil, false
    }
}

repl_wait_for_debug_continue :: proc(
    protocol_reader: ^bufio.Reader,
    worker: ^Repl_Worker_Process,
    session: ^Repl_Session,
    parent_request: ^Repl_Request,
    input,
    session_dir: string,
    generation_counter: ^int,
    nesting_depth: int,
    pause_id: string,
    generation: int,
    local_values: []string = nil,
    collections: []Repl_Debug_Collection = nil,
    condition_type := "",
    condition_message := "",
    condition_data := "",
    condition_value_type := "",
    condition_restart_flags: u32 = 0,
) -> bool {
    source_line, has_source_line := parent_request.line.(int)
    source_column, has_source_column := parent_request.column.(int)
    frame := Repl_Debug_Frame{
        frame_id = fmt.tprintf("frame-%s", pause_id),
        pause_id = pause_id,
        generation = generation,
        source_path = parent_request.source_path,
        line = source_line if has_source_line else 1,
        column = source_column if has_source_column else 1,
        phase = "before-eval",
    }
    base_frame := frame
    if retained_frame, found :=
        repl_session_debug_frame(session, pause_id); found {
        base_frame = retained_frame^
    }
    frame = repl_debug_frame_clone(base_frame)
    defer repl_debug_frame_delete(&frame)
    for collection in collections {
        append(&frame.collections, Repl_Debug_Collection{
            path = strings.clone(collection.path),
            shape = strings.clone(collection.shape),
            element_type = strings.clone(collection.element_type),
            key_type = strings.clone(collection.key_type),
            value_type = strings.clone(collection.value_type),
            descriptor = collection.descriptor,
        })
    }
    value_i := 0
    for &local in frame.locals {
        if value_i >= len(local_values) {
            break
        }
        delete(local.value)
        local.value = strings.clone(local_values[value_i])
        value_i += 1
        if local.key_type != "" && local.value_type != "" {
            if value_i >= len(local_values) {
                break
            }
            total, total_ok :=
                strconv.parse_int(local_values[value_i])
            value_i += 1
            if total_ok && total >= 0 {
                capture_limit := max(
                    1,
                    REPL_DEBUG_DYNAMIC_ARRAY_LIMIT/
                        (1+len(local.map_value_paths)),
                )
                local.capture_limit =
                    Repl_Optional_Int(capture_limit)
                local.total = Repl_Optional_Int(total)
                local.truncated = Repl_Optional_Bool(
                    total > capture_limit,
                )
                captured := min(total, capture_limit)
                for _ in 0..<captured {
                    if value_i+1 >= len(local_values) {
                        break
                    }
                    key_source := local_values[value_i]
                    value_i += 1
                    value_root := fmt.tprintf("[%s]", key_source)
                    append(&local.paths, Repl_Debug_Path{
                        path = strings.clone(value_root),
                        ty = strings.clone(local.value_type),
                        value =
                            strings.clone(local_values[value_i]),
                    })
                    value_i += 1
                    for value_path in local.map_value_paths {
                        if value_i >= len(local_values) {
                            break
                        }
                        expanded_path := ""
                        if strings.has_prefix(
                            value_path.path,
                            "[",
                        ) {
                            expanded_path = fmt.tprintf(
                                "%s%s",
                                value_root,
                                value_path.path,
                            )
                        } else {
                            expanded_path = fmt.tprintf(
                                "%s.%s",
                                value_root,
                                value_path.path,
                            )
                        }
                        append(&local.paths, Repl_Debug_Path{
                            path = strings.clone(expanded_path),
                            ty = strings.clone(value_path.ty),
                            value = strings.clone(
                                local_values[value_i],
                            ),
                        })
                        value_i += 1
                    }
                }
            }
            continue
        }
        if local.element_type != "" {
            if value_i >= len(local_values) {
                break
            }
            total, total_ok :=
                strconv.parse_int(local_values[value_i])
            value_i += 1
            if total_ok && total >= 0 {
                capture_limit := max(
                    1,
                    REPL_DEBUG_DYNAMIC_ARRAY_LIMIT/
                        (1+len(local.element_paths)),
                )
                local.capture_limit =
                    Repl_Optional_Int(capture_limit)
                local.total = Repl_Optional_Int(total)
                local.truncated = Repl_Optional_Bool(
                    total > capture_limit,
                )
                captured := min(total, capture_limit)
                for i in 0..<captured {
                    if value_i >= len(local_values) {
                        break
                    }
                    element_root := fmt.tprintf("[%d]", i)
                    append(&local.paths, Repl_Debug_Path{
                        path = strings.clone(element_root),
                        ty = strings.clone(local.element_type),
                        value =
                            strings.clone(local_values[value_i]),
                    })
                    value_i += 1
                    for element_path in local.element_paths {
                        if value_i >= len(local_values) {
                            break
                        }
                        expanded_path := ""
                        if strings.has_prefix(
                            element_path.path,
                            "[",
                        ) {
                            expanded_path = fmt.tprintf(
                                "%s%s",
                                element_root,
                                element_path.path,
                            )
                        } else {
                            expanded_path = fmt.tprintf(
                                "%s.%s",
                                element_root,
                                element_path.path,
                            )
                        }
                        append(&local.paths, Repl_Debug_Path{
                            path = strings.clone(expanded_path),
                            ty = strings.clone(element_path.ty),
                            value = strings.clone(
                                local_values[value_i],
                            ),
                        })
                        value_i += 1
                    }
                }
            }
            continue
        }
        for &path in local.paths {
            if value_i >= len(local_values) {
                break
            }
            delete(path.value)
            path.value = strings.clone(local_values[value_i])
            value_i += 1
        }
    }
    frames := [1]Repl_Debug_Frame{frame}
    restarts: [5]Repl_Restart
    restart_count := 0
    if condition_type != "" {
        if condition_restart_flags&REPL_RESTART_CONTINUE != 0 {
            restarts[restart_count] = Repl_Restart{
                name = "continue",
                label = "Continue from this safe point",
            }
            restart_count += 1
        }
        if condition_restart_flags&REPL_RESTART_USE_VALUE != 0 &&
           condition_value_type != "" {
            restarts[restart_count] = Repl_Restart{
                name = "use-value",
                label = "Replace the mutable local and continue",
                requires_value = true,
                value_type = condition_value_type,
            }
            restart_count += 1
        }
        if condition_restart_flags&REPL_RESTART_RETRY != 0 {
            restarts[restart_count] = Repl_Restart{
                name = "retry",
                label = "Retry the enclosing restart case",
            }
            restart_count += 1
        }
        if condition_restart_flags&REPL_RESTART_SKIP != 0 {
            restarts[restart_count] = Repl_Restart{
                name = "skip",
                label = "Skip the rest of the enclosing restart case",
            }
            restart_count += 1
        }
        if condition_restart_flags&
            REPL_RESTART_ABORT_OPERATION != 0 {
            restarts[restart_count] = Repl_Restart{
                name = "abort-operation",
                label = "Abort the enclosing debug operation",
            }
            restart_count += 1
        }
    }
    available_restarts := restarts[:restart_count]
    repl_emit_json_event(Repl_Event{
        protocol_version = REPL_PROTOCOL_VERSION,
        id = parent_request.id,
        kind = "condition" if condition_type != "" else "paused",
        success = true,
        generation = generation,
        message = condition_message,
        pause_id = pause_id,
        condition_type = condition_type,
        condition_data = condition_data,
        restarts = available_restarts,
        source_path = frame.source_path,
        line = Repl_Optional_Int(frame.line),
        column = Repl_Optional_Int(frame.column),
        frames = frames[:],
    })
    for {
        raw, ok := repl_read_line(protocol_reader)
        if !ok {
            repl_resume_paused_worker(worker)
            return false
        }
        line := repl_trim_line(raw)
        control := Repl_Request{}
        unmarshal_err := json.unmarshal(transmute([]byte)line, &control)
        delete(raw)
        if unmarshal_err != nil {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                kind = "protocol-error",
                success = false,
                generation = generation,
                message = "invalid JSONL request while paused",
            })
            repl_delete_request(&control)
            continue
        }
        if control.op == "interrupt" &&
           (control.pause_id == "" ||
            control.pause_id == pause_id) {
            terminate_err := os.process_terminate(worker.process)
            if terminate_err != nil {
                _ = os.process_kill(worker.process)
            }
            _, _ = os.process_wait(worker.process)
            worker.alive = false
            worker.termination_kind = "interrupt"
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "interrupted",
                success = true,
                generation = generation,
                pause_id = pause_id,
                message =
                    "standalone REPL worker terminated; runtime session state was discarded",
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&control)
            return false
        }
        if (control.op == "debug-continue" ||
            control.op == "debug-step" ||
            control.op == "debug-step-over" ||
            control.op == "debug-step-out") &&
           (control.pause_id == "" ||
            control.pause_id == pause_id) {
            stepping := control.op != "debug-continue"
            if stepping {
                step_command := "__step_into__"
                if control.op == "debug-step-over" {
                    step_command = "__step_over__"
                } else if control.op == "debug-step-out" {
                    step_command = "__step_out__"
                }
                repl_step_paused_worker(worker, step_command)
            } else {
                repl_resume_paused_worker(worker)
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "stepping" if stepping else "resumed",
                success = true,
                generation = generation,
                pause_id = pause_id,
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&control)
            return true
        }
        if control.op == "debug-abort" &&
           (control.pause_id == "" ||
            control.pause_id == pause_id) {
            repl_abort_paused_worker(worker)
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "abort-requested",
                success = true,
                generation = generation,
                pause_id = pause_id,
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&control)
            return true
        }
        if control.op == "debug-restart" &&
           (control.pause_id == "" ||
            control.pause_id == pause_id) {
            restart_name := strings.trim_space(control.name)
            if restart_name == "" {
                restart_name = strings.trim_space(control.source)
            }
            restart_available :=
                condition_type != "" &&
                ((restart_name == "continue" &&
                  condition_restart_flags&REPL_RESTART_CONTINUE != 0) ||
                 (restart_name == "use-value" &&
                  condition_restart_flags&REPL_RESTART_USE_VALUE != 0 &&
                  condition_value_type != "") ||
                 (restart_name == "retry" &&
                  condition_restart_flags&REPL_RESTART_RETRY != 0) ||
                 (restart_name == "skip" &&
                  condition_restart_flags&REPL_RESTART_SKIP != 0) ||
                 (restart_name == "abort-operation" &&
                  condition_restart_flags&
                      REPL_RESTART_ABORT_OPERATION != 0))
            restart_value := control.source
            value_valid := true
            if restart_name == "use-value" {
                restart_value = strings.trim_space(restart_value)
                if condition_value_type == "int" {
                    _, value_valid =
                        strconv.parse_int(restart_value)
                } else if condition_value_type == "bool" {
                    value_valid =
                        restart_value == "true" ||
                        restart_value == "false"
                } else if condition_value_type == "f32" {
                    _, value_valid =
                        strconv.parse_f32(restart_value)
                } else if condition_value_type == "f64" {
                    _, value_valid =
                        strconv.parse_f64(restart_value)
                } else if condition_value_type == "string" {
                    restart_value = control.source
                } else {
                    value_valid = false
                }
            }
            if !restart_available || !value_valid {
                message :=
                    "restart is not available for the active pause"
                if restart_available && !value_valid {
                    message = fmt.tprintf(
                        "use-value expects a valid %s value",
                        condition_value_type,
                    )
                }
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = control.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message = message,
                })
                repl_delete_request(&control)
                continue
            }
            if restart_name == "continue" {
                repl_resume_paused_worker(worker)
            } else {
                repl_restart_paused_worker(
                    worker,
                    restart_name,
                    restart_value,
                )
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "restart-invoked",
                success = true,
                generation = generation,
                pause_id = pause_id,
                restart = restart_name,
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&control)
            return true
        }
        if control.op == "debug-eval-native" &&
           (control.pause_id == "" ||
            control.pause_id == pause_id) {
            nested_message := ""
            nested_allowed :=
                generation_counter != nil &&
                input != "" &&
                session_dir != "" &&
                nesting_depth < 8 &&
                !control.trace
            parent_definitions :=
                kvist.repl_persistent_definitions_source(
                    parent_request.source,
                )
            parent_has_definitions := parent_definitions != ""
            delete(parent_definitions)
            if parent_has_definitions {
                nested_allowed = false
                nested_message =
                    "native break evaluation requires an expression-only suspended request"
            } else if nesting_depth >= 8 {
                nested_message =
                    "native break evaluation nesting limit reached"
            } else if control.trace {
                nested_message =
                    "native break evaluation does not support tracing"
            } else if !nested_allowed {
                nested_message =
                    "native break evaluation is unavailable for this pause"
            }
            if !nested_allowed {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = control.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message = nested_message,
                })
                repl_delete_request(&control)
                continue
            }

            generation_counter^ += 1
            nested_generation := generation_counter^
            nested_line, nested_has_line := control.line.(int)
            nested_column, nested_has_column :=
                control.column.(int)
            nested_pause_id := ""
            if control.pause_before {
                nested_pause_id =
                    strings.clone(
                        fmt.tprintf(
                            "pause-%d",
                            nested_generation,
                        ),
                    )
            }
            nested_output := ""
            nested_ok := false
            nested_output, nested_message, nested_ok =
                repl_handle_eval(
                    input,
                    control.source,
                    session_dir,
                    nested_generation,
                    control.no_print,
                    worker,
                    session,
                    control.source_path,
                    nested_line if nested_has_line else 1,
                    nested_column if nested_has_column else 1,
                    nested_pause_id,
                    protocol_reader,
                    &control,
                    false,
                    nil,
                    "",
                    "",
                    "",
                    0,
                    0,
                    false,
                    REPL_DEFAULT_TRACE_LIMIT,
                    false,
                    REPL_DEFAULT_TRACE_VALUE_LIMIT,
                    generation_counter,
                    true,
                    nesting_depth+1,
                    execution_mode = .Native,
                )
            nested_stderr := repl_worker_take_stderr(worker)
            delete(nested_pause_id)

            for loaded, loaded_index in session.generations {
                if loaded.generation == nested_generation {
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = control.id,
                        kind = "generation-loaded",
                        success = true,
                        generation = nested_generation,
                        generations =
                            session.generations[
                                loaded_index:loaded_index+1
                            ],
                    })
                    break
                }
            }
            if nested_output != "" {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = control.id,
                    kind = "output",
                    success = true,
                    generation = nested_generation,
                    stream = "stdout",
                    text = nested_output,
                })
            }
            if nested_stderr != "" {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = control.id,
                    kind = "output",
                    success = true,
                    generation = nested_generation,
                    stream = "stderr",
                    text = nested_stderr,
                })
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = nested_ok,
                generation = nested_generation,
                message = nested_message,
            })
            delete(nested_output)
            delete(nested_stderr)
            delete(nested_message)
            repl_delete_request(&control)
            if !worker.alive {
                return false
            }

            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = parent_request.id,
                kind =
                    "condition" if condition_type != "" else
                        "paused",
                success = true,
                generation = generation,
                message = condition_message,
                pause_id = pause_id,
                condition_type = condition_type,
                restarts = available_restarts,
                source_path = frame.source_path,
                line = Repl_Optional_Int(frame.line),
                column = Repl_Optional_Int(frame.column),
                frames = frames[:],
            })
            continue
        }
        if control.op == "debug-frame" &&
           (control.pause_id == "" ||
            control.pause_id == pause_id) {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "debug-frame",
                success = true,
                generation = generation,
                pause_id = pause_id,
                source_path = frame.source_path,
                line = Repl_Optional_Int(frame.line),
                column = Repl_Optional_Int(frame.column),
                frames = frames[:],
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&control)
            continue
        }
        if control.op == "debug-page" &&
           (control.pause_id == "" ||
            control.pause_id == pause_id) {
            requested_path := strings.trim_space(control.source)
            mapped_path := kvist.map_name(requested_path)
            collection_index := -1
            for collection, index in frame.collections {
                if collection.path == requested_path ||
                   collection.path == mapped_path {
                    collection_index = index
                    break
                }
            }
            delete(mapped_path)
            offset, has_offset := control.offset.(int)
            if !has_offset {
                offset = 0
            }
            limit, has_limit := control.limit.(int)
            if !has_limit {
                limit = REPL_DEFAULT_PAGE_LIMIT
            }
            valid := collection_index >= 0 &&
                     offset >= 0 &&
                     limit > 0 &&
                     limit <= REPL_MAX_PAGE_LIMIT
            if !valid {
                message := "invalid paused collection page request"
                if collection_index < 0 {
                    message =
                        "collection path is not pageable in the active frame"
                }
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = control.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message = message,
                })
                repl_delete_request(&control)
                continue
            }
            collection := frame.collections[collection_index]
            page_entries, page_total, discovered, page_ok :=
                repl_debug_page_worker(
                    worker,
                    collection.descriptor,
                    offset,
                    limit,
                )
            if !page_ok {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = control.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message =
                        "paused collection page capture failed",
                })
                delete(discovered)
                repl_delete_request(&control)
                continue
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "debug-page",
                success = true,
                generation = generation,
                pause_id = pause_id,
                collection_path = collection.path,
                shape = collection.shape,
                element_type = collection.element_type,
                key_type = collection.key_type,
                value_type = collection.value_type,
                offset = Repl_Optional_Int(offset),
                limit = Repl_Optional_Int(limit),
                total = Repl_Optional_Int(page_total),
                entries = page_entries[:],
                collections = discovered[:],
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            for collection in discovered {
                append(&frame.collections, collection)
            }
            delete(discovered)
            repl_inspection_entries_delete(page_entries[:])
            repl_delete_request(&control)
            continue
        }
        if control.op == "debug-eval" &&
           (control.pause_id == "" ||
            control.pause_id == pause_id) {
            expression, _, expression_ok :=
                kvist.read_single_eval_form(control.source)
            result_text := ""
            result_type := ""
            eval_message := ""
            evaluated := false
            direct_source := strings.trim_space(control.source)
            direct_type, direct_value, direct_found :=
                repl_debug_snapshot_lookup(
                    &frame,
                    direct_source,
                )
            if direct_found {
                result_type = direct_type
                result_text = direct_value
                evaluated = true
            } else if !expression_ok {
                eval_message =
                    "debug-eval expects exactly one readable expression"
            } else if expression.kind == .Symbol {
                result_type, result_text, evaluated =
                    repl_debug_snapshot_lookup(
                        &frame,
                        expression.text,
                    )
                if !evaluated {
                    eval_message = fmt.tprintf(
                        "local is not visible in the active frame: %s",
                        expression.text,
                    )
                }
            } else {
                _, type_message, type_ok :=
                    repl_debug_eval_infer_kind(&frame, expression)
                if type_ok {
                    value, value_message, value_ok :=
                        repl_debug_eval_form(&frame, expression)
                    if value_ok {
                        render_ok: bool
                        result_text, result_type, render_ok =
                            repl_debug_eval_render(value)
                        evaluated = render_ok
                        if !render_ok {
                            eval_message =
                                "paused expression produced an unsupported value"
                        }
                    } else {
                        eval_message = value_message
                    }
                } else {
                    eval_message = type_message
                }
            }
            if !evaluated {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = control.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message = eval_message,
                })
                repl_delete_request(&control)
                continue
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "debug-value",
                success = true,
                generation = generation,
                pause_id = pause_id,
                text = result_text,
                ty = result_type,
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&control)
            continue
        }
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = control.id,
            kind = "complete",
            success = false,
            generation = generation,
            message =
                "REPL is paused; send debug-frame, debug-page, debug-eval, debug-eval-native, debug-restart, debug-step, debug-step-over, debug-step-out, debug-continue, debug-abort, or interrupt with the active pause_id",
        })
        repl_delete_request(&control)
    }
}

repl_worker_run_generation :: proc(
    worker: ^Repl_Worker_Process,
    path: string,
    protocol_reader: ^bufio.Reader = nil,
    parent_request: ^Repl_Request = nil,
    session: ^Repl_Session = nil,
    generation := 0,
    trace := false,
    trace_limit := REPL_DEFAULT_TRACE_LIMIT,
    trace_values := false,
    trace_value_limit := REPL_DEFAULT_TRACE_VALUE_LIMIT,
    pending_frames: []Repl_Debug_Frame = nil,
    input := "",
    session_dir := "",
    generation_counter: ^int = nil,
    nested_worker_execution := false,
    nesting_depth := 0,
    timeout_ms := 0,
    timings: ^Repl_Eval_Timings = nil,
) -> (
    output: string,
    message: string,
    ok: bool,
) {
    if !worker.alive {
        return "", strings.clone("REPL worker is not running"), false
    }
    delete(worker.captured_stderr)
    worker.captured_stderr = ""
    defer repl_worker_capture_stderr(worker)
    if trace && !nested_worker_execution {
        trace_config :=
            fmt.aprintf(
                "__trace_next__\t%d\t%d\n",
                trace_limit,
                trace_value_limit if trace_values else 0,
            )
        defer delete(trace_config)
        _, trace_write_err :=
            os.write_string(worker.input, trace_config)
        if trace_write_err != nil {
            worker.alive = false
            worker.termination_kind = "crash"
            return "",
                   strings.clone(
                       "REPL worker exited before trace configuration",
                   ),
                   false
        }
    }
    write_err: os.Error
    if nested_worker_execution {
        encoded_path := repl_debug_hex_encode(path)
        _, write_err = os.write_strings(
            worker.input,
            "__nested__\t",
            encoded_path,
            "\n",
        )
        delete(encoded_path)
    } else {
        _, write_err = os.write_strings(worker.input, path, "\n")
    }
    if write_err != nil {
        worker.alive = false
        worker.termination_kind = "crash"
        return "", strings.clone("REPL worker exited before generation execution"), false
    }
    _ = os.flush(worker.input)

    watchdog := Repl_Deadline_Watchdog{
        process = worker.process,
        timeout_ms = timeout_ms,
    }
    watchdog_thread: ^thread.Thread
    if timeout_ms > 0 {
        watchdog_thread =
            thread.create_and_start_with_data(
                rawptr(&watchdog),
                repl_deadline_watchdog_run,
            )
    }
    defer repl_deadline_watchdog_finish(
        &watchdog,
        watchdog_thread,
    )

    captured := strings.builder_make()
    defer strings.builder_destroy(&captured)
    trace_hotspots: [dynamic]Repl_Trace_Hotspot
    defer repl_trace_hotspots_delete(&trace_hotspots)
    previous_trace := Repl_Trace_Sample{}
    defer repl_trace_sample_delete(&previous_trace)
    has_previous_trace := false
    trace_points := 0
    trace_unattributed_ns := 0
    trace_truncated := false
    trace_truncated_at_ns := 0
    pending_condition_pause_id := ""
    pending_condition_type := ""
    pending_condition_message := ""
    pending_condition_data := ""
    pending_condition_value_type := ""
    pending_condition_restart_flags: u32
    aborted := false
    defer {
        delete(pending_condition_pause_id)
        delete(pending_condition_type)
        delete(pending_condition_message)
        delete(pending_condition_data)
        delete(pending_condition_value_type)
    }
    for {
        raw, read_ok := repl_read_line(&worker.reader)
        if !read_ok {
            state, _ := os.process_wait(worker.process)
            worker.alive = false
            if repl_deadline_watchdog_timed_out(&watchdog) {
                worker.termination_kind = "deadline"
                if state.exited {
                    worker.exit_code = state.exit_code
                    worker.has_exit_code = true
                }
                return strings.clone(strings.to_string(captured)),
                       strings.clone(
                           fmt.tprintf(
                               "evaluation deadline exceeded after %d ms",
                               timeout_ms,
                           ),
                       ),
                       false
            }
            worker.termination_kind = "crash"
            if state.exited {
                worker.exit_code = state.exit_code
                worker.has_exit_code = true
                return strings.clone(strings.to_string(captured)),
                       strings.clone(fmt.tprintf("REPL worker exited with status %d", state.exit_code)),
                       false
            }
            return strings.clone(strings.to_string(captured)),
                   strings.clone("REPL worker exited during generation execution"),
                   false
        }
        line := repl_trim_line(raw)
        if line == REPL_WORKER_ABORTED_MARKER {
            aborted = true
            delete(raw)
            continue
        }
        if strings.has_prefix(line, REPL_WORKER_STREAM_OUTPUT_MARKER) {
            streamed, decoded :=
                repl_debug_hex_decode(
                    line[len(REPL_WORKER_STREAM_OUTPUT_MARKER):],
                )
            if decoded {
                if parent_request != nil {
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = parent_request.id,
                        kind = "stream-output",
                        success = true,
                        generation = generation,
                        stream = "stdout",
                        text = streamed,
                    })
                } else {
                    strings.write_string(&captured, streamed)
                }
            }
            delete(streamed)
            delete(raw)
            continue
        }
        if strings.has_prefix(line, REPL_WORKER_TRACE_MARKER) {
            fields :=
                strings.split(
                    line[len(REPL_WORKER_TRACE_MARKER):],
                    "\t",
                    context.allocator,
                )
            if len(fields) == 4 &&
               protocol_reader != nil &&
               parent_request != nil {
                depth, depth_ok := strconv.parse_int(fields[1])
                elapsed_ns, elapsed_ok := strconv.parse_int(fields[2])
                delta_ns, delta_ok := strconv.parse_int(fields[3])
                frame, frame_ok :=
                    repl_trace_frame(
                        session,
                        pending_frames,
                        fields[0],
                    )
                if depth_ok && elapsed_ok && delta_ok {
                    if has_previous_trace {
                        repl_trace_add_interval(
                            &trace_hotspots,
                            previous_trace,
                            delta_ns,
                        )
                    } else {
                        trace_unattributed_ns += max(delta_ns, 0)
                    }
                    repl_trace_sample_set(
                        &previous_trace,
                        frame,
                        frame_ok,
                        fields[0],
                        elapsed_ns,
                    )
                    has_previous_trace = true
                    trace_points += 1
                    event := Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = parent_request.id,
                        kind = "trace",
                        success = true,
                        generation = generation,
                        trace_id = fields[0],
                        depth = Repl_Optional_Int(depth),
                        elapsed_ns = Repl_Optional_Int(elapsed_ns),
                        delta_ns = Repl_Optional_Int(delta_ns),
                    }
                    if frame_ok {
                        event.source_path = frame.source_path
                        event.line = Repl_Optional_Int(frame.line)
                        event.column = Repl_Optional_Int(frame.column)
                    }
                    repl_emit_json_event(event)
                }
            }
            delete(fields)
            delete(raw)
            continue
        }
        if strings.has_prefix(line, REPL_WORKER_TRACE_VALUES_MARKER) {
            fields :=
                strings.split(
                    line[len(REPL_WORKER_TRACE_VALUES_MARKER):],
                    "\t",
                    context.allocator,
                )
            if len(fields) >= 2 &&
               protocol_reader != nil &&
               parent_request != nil {
                value_count, value_count_ok :=
                    strconv.parse_int(fields[1])
                frame, frame_ok :=
                    repl_trace_frame(
                        session,
                        pending_frames,
                        fields[0],
                    )
                if value_count_ok &&
                   value_count >= 0 &&
                   len(fields) == value_count+2 &&
                   frame_ok {
                    values: [dynamic]Repl_Trace_Value
                    values_ok := true
                    for encoded, value_index in fields[2:] {
                        rendered, decoded :=
                            repl_debug_hex_decode(encoded)
                        if !decoded ||
                           value_index >= len(frame.locals) {
                            delete(rendered)
                            values_ok = false
                            break
                        }
                        local := frame.locals[value_index]
                        append(&values, Repl_Trace_Value{
                            name = local.name,
                            ty = local.ty,
                            mutable = local.mutable,
                            ownership = local.ownership,
                            value = rendered,
                        })
                    }
                    if values_ok {
                        repl_emit_json_event(Repl_Event{
                            protocol_version =
                                REPL_PROTOCOL_VERSION,
                            id = parent_request.id,
                            kind = "trace-values",
                            success = true,
                            generation = generation,
                            trace_id = fields[0],
                            source_path = frame.source_path,
                            line = Repl_Optional_Int(frame.line),
                            column =
                                Repl_Optional_Int(frame.column),
                            trace_values = values[:],
                        })
                    }
                    for value in values {
                        delete(value.value)
                    }
                    delete(values)
                }
            }
            delete(fields)
            delete(raw)
            continue
        }
        if line == REPL_WORKER_TRACE_VALUES_LIMIT_MARKER {
            if parent_request != nil {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = parent_request.id,
                    kind = "trace-values-limit",
                    success = true,
                    generation = generation,
                    message =
                        "instrumented trace value limit reached; later safe-point values were omitted",
                })
            }
            delete(raw)
            continue
        }
        if strings.has_prefix(line, REPL_WORKER_TRACE_LIMIT_MARKER) {
            elapsed_ns, elapsed_ok :=
                strconv.parse_int(
                    line[len(REPL_WORKER_TRACE_LIMIT_MARKER):],
                )
            if elapsed_ok {
                if has_previous_trace {
                    repl_trace_add_interval(
                        &trace_hotspots,
                        previous_trace,
                        elapsed_ns-previous_trace.elapsed_ns,
                    )
                    repl_trace_sample_delete(&previous_trace)
                    has_previous_trace = false
                }
                trace_truncated = true
                trace_truncated_at_ns = max(elapsed_ns, 0)
            }
            if parent_request != nil {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = parent_request.id,
                    kind = "trace-limit",
                    success = true,
                    generation = generation,
                    message =
                        "instrumented trace limit reached; remaining safe points were omitted",
                })
            }
            delete(raw)
            continue
        }
        if strings.has_prefix(line, REPL_WORKER_TRACE_END_MARKER) {
            total_ns, total_ok :=
                strconv.parse_int(
                    line[len(REPL_WORKER_TRACE_END_MARKER):],
                )
            if total_ok && parent_request != nil {
                total_ns = max(total_ns, 0)
                if trace_truncated {
                    trace_unattributed_ns +=
                        max(total_ns-trace_truncated_at_ns, 0)
                } else if has_previous_trace {
                    repl_trace_add_interval(
                        &trace_hotspots,
                        previous_trace,
                        total_ns-previous_trace.elapsed_ns,
                    )
                } else {
                    trace_unattributed_ns += total_ns
                }
                repl_trace_hotspots_sort(&trace_hotspots)
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = parent_request.id,
                    kind = "trace-summary",
                    success = true,
                    generation = generation,
                    trace_points = Repl_Optional_Int(trace_points),
                    trace_total_ns = Repl_Optional_Int(total_ns),
                    trace_unattributed_ns =
                        Repl_Optional_Int(trace_unattributed_ns),
                    hotspots = trace_hotspots[:],
                })
            }
            delete(raw)
            continue
        }
        if strings.has_prefix(line, REPL_WORKER_CONDITION_MARKER) {
            fields :=
                strings.split(
                    line[len(REPL_WORKER_CONDITION_MARKER):],
                    "\t",
                    context.allocator,
                )
            if len(fields) == 6 {
                condition_type, type_ok :=
                    repl_debug_hex_decode(fields[1])
                condition_message, message_ok :=
                    repl_debug_hex_decode(fields[2])
                condition_data, data_ok :=
                    repl_debug_hex_decode(fields[3])
                condition_value_type := ""
                value_type_ok := fields[4] == "-"
                if value_type_ok {
                    condition_value_type = strings.clone("")
                } else {
                    condition_value_type, value_type_ok =
                        repl_debug_hex_decode(fields[4])
                }
                parsed_restart_flags, restart_flags_ok :=
                    strconv.parse_uint(fields[5])
                if type_ok && message_ok && data_ok && value_type_ok &&
                   restart_flags_ok &&
                   parsed_restart_flags <= 0xffff_ffff {
                    delete(pending_condition_pause_id)
                    delete(pending_condition_type)
                    delete(pending_condition_message)
                    delete(pending_condition_data)
                    delete(pending_condition_value_type)
                    pending_condition_pause_id =
                        strings.clone(fields[0])
                    pending_condition_type = condition_type
                    pending_condition_message = condition_message
                    pending_condition_data = condition_data
                    pending_condition_value_type =
                        condition_value_type
                    pending_condition_restart_flags =
                        u32(parsed_restart_flags)
                } else {
                    delete(condition_type)
                    delete(condition_message)
                    delete(condition_data)
                    delete(condition_value_type)
                }
            }
            delete(fields)
            delete(raw)
            continue
        }
        if strings.has_prefix(line, REPL_WORKER_PAUSED_MARKER) {
            fields :=
                strings.split(
                    line[len(REPL_WORKER_PAUSED_MARKER):],
                    "\t",
                    context.allocator,
                )
            pause_id := fields[0]
            local_values: [dynamic]string
            collections: [dynamic]Repl_Debug_Collection
            values_ok := true
            collections_start := len(fields)
            values_end := len(fields)
            for field, index in fields[1:] {
                if field == REPL_WORKER_DEBUG_COLLECTIONS_MARKER {
                    values_end = index+1
                    collections_start = index+2
                    break
                }
            }
            for encoded in fields[1:values_end] {
                value, decoded := repl_debug_hex_decode(encoded)
                if !decoded {
                    values_ok = false
                    break
                }
                append(&local_values, value)
            }
            if values_ok && collections_start < len(fields) {
                for encoded, descriptor in
                    fields[collections_start:] {
                    parts := strings.split(
                        encoded,
                        "=",
                        context.allocator,
                    )
                    if len(parts) != 5 ||
                       len(parts[0]) == 0 ||
                       len(parts[1]) == 0 {
                        delete(parts)
                        values_ok = false
                        break
                    }
                    path, path_ok :=
                        repl_debug_hex_decode(parts[0])
                    shape, shape_ok :=
                        repl_debug_hex_decode(parts[1])
                    element_type, element_type_ok :=
                        repl_debug_hex_decode(parts[2])
                    key_type, key_type_ok :=
                        repl_debug_hex_decode(parts[3])
                    value_type, value_type_ok :=
                        repl_debug_hex_decode(parts[4])
                    delete(parts)
                    if !path_ok || !shape_ok ||
                       !element_type_ok || !key_type_ok ||
                       !value_type_ok {
                        delete(path)
                        delete(shape)
                        delete(element_type)
                        delete(key_type)
                        delete(value_type)
                        values_ok = false
                        break
                    }
                    append(&collections, Repl_Debug_Collection{
                        path = path,
                        shape = shape,
                        element_type = element_type,
                        key_type = key_type,
                        value_type = value_type,
                        descriptor = descriptor,
                    })
                }
            }
            active_condition_type := ""
            active_condition_message := ""
            active_condition_data := ""
            active_condition_value_type := ""
            active_condition_restart_flags: u32
            if pending_condition_pause_id == pause_id {
                active_condition_type = pending_condition_type
                active_condition_message = pending_condition_message
                active_condition_data = pending_condition_data
                active_condition_value_type =
                    pending_condition_value_type
                active_condition_restart_flags =
                    pending_condition_restart_flags
            }
            continued :=
                values_ok &&
                protocol_reader != nil &&
                parent_request != nil &&
                session != nil &&
                repl_wait_for_debug_continue(
                    protocol_reader,
                    worker,
                    session,
                    parent_request,
                    input,
                    session_dir,
                    generation_counter,
                    nesting_depth,
                    pause_id,
                    generation,
                    local_values[:],
                    collections[:],
                    active_condition_type,
                    active_condition_message,
                    active_condition_data,
                    active_condition_value_type,
                    active_condition_restart_flags,
                )
            delete(pending_condition_pause_id)
            delete(pending_condition_type)
            delete(pending_condition_message)
            delete(pending_condition_data)
            delete(pending_condition_value_type)
            pending_condition_pause_id = ""
            pending_condition_type = ""
            pending_condition_message = ""
            pending_condition_data = ""
            pending_condition_value_type = ""
            pending_condition_restart_flags = 0
            for value in local_values {
                delete(value)
            }
            delete(local_values)
            for &collection in collections {
                delete(collection.path)
                delete(collection.shape)
                delete(collection.element_type)
                delete(collection.key_type)
                delete(collection.value_type)
            }
            delete(collections)
            delete(fields)
            delete(raw)
            if !continued {
                if !values_ok ||
                   protocol_reader == nil ||
                   parent_request == nil ||
                   session == nil {
                    repl_resume_paused_worker(worker)
                }
                return strings.clone(strings.to_string(captured)),
                       strings.clone("debug pause ended before continuation"),
                       false
            }
            continue
        }
        if strings.has_prefix(line, REPL_WORKER_MARKER) {
            status := line[len(REPL_WORKER_MARKER):]
            fields := strings.split(status, "\t", context.allocator)
            if len(fields) > 0 && fields[0] == "ok" &&
               (len(fields) == 1 || len(fields) == 3) {
                if len(fields) == 3 {
                    load_ns, load_ok := strconv.parse_int(fields[1])
                    run_ns, run_ok := strconv.parse_int(fields[2])
                    if timings != nil && load_ok && run_ok {
                        timings.worker_load_ns = i64(load_ns)
                        timings.native_run_ns = i64(run_ns)
                    }
                }
                delete(fields)
                delete(raw)
                return strings.clone(strings.to_string(captured)),
                       strings.clone(REPL_EVALUATION_ABORTED_MESSAGE) if
                           aborted else "",
                       true
            }
            delete(fields)
            message_text := fmt.tprintf("unexpected REPL worker response: %q", status)
            if strings.has_prefix(status, "error\t") {
                message_text = status[len("error\t"):]
            }
            message = strings.clone(message_text)
            delete(raw)
            return strings.clone(strings.to_string(captured)), message, false
        }
        strings.write_string(&captured, raw)
        delete(raw)
    }
}

repl_generation_paths :: proc(session_dir: string, generation: int) -> (
    source_path,
    library_path: string,
    ok: bool,
) {
    source_name := fmt.tprintf("generation_%04d.odin", generation)
    source_err: os.Error
    source_path, source_err = os.join_path({session_dir, source_name}, context.allocator)
    if source_err != nil {
        return "", "", false
    }
    library_name := fmt.tprintf("generation_%04d.%s", generation, dynlib.LIBRARY_FILE_EXTENSION)
    library_err: os.Error
    library_path, library_err = os.join_path({session_dir, library_name}, context.allocator)
    if library_err != nil {
        delete(source_path)
        return "", "", false
    }
    return source_path, library_path, true
}

repl_generation_map_path :: proc(
    session_dir: string,
    generation: int,
) -> (string, bool) {
    map_name := fmt.tprintf("generation_%04d.map", generation)
    map_path, map_err :=
        os.join_path({session_dir, map_name}, context.allocator)
    return map_path, map_err == nil
}

repl_breakpoint_locations_delete :: proc(
    locations: ^[dynamic]Repl_Breakpoint_Location,
) {
    for &location in locations {
        delete(location.source_path)
        delete(location.generated_path)
    }
    delete(locations^)
    locations^ = nil
}

repl_debug_frames_delete :: proc(frames: ^[dynamic]Repl_Debug_Frame) {
    for &frame in frames {
        delete(frame.frame_id)
        delete(frame.pause_id)
        delete(frame.definition_name)
        delete(frame.source_path)
        delete(frame.phase)
        for &local in frame.locals {
            repl_debug_local_delete(&local)
        }
        delete(frame.locals)
        for &collection in frame.collections {
            delete(collection.path)
            delete(collection.shape)
            delete(collection.element_type)
            delete(collection.key_type)
            delete(collection.value_type)
        }
        delete(frame.collections)
    }
    delete(frames^)
    frames^ = nil
}

repl_debug_hex_nibble :: proc(byte: u8) -> (u8, bool) {
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

repl_debug_hex_encode :: proc(value: string) -> string {
    digits := "0123456789abcdef"
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for byte in transmute([]byte)value {
        strings.write_byte(&builder, digits[int(byte >> 4)])
        strings.write_byte(&builder, digits[int(byte & 0xf)])
    }
    return strings.clone(strings.to_string(builder))
}

repl_debug_hex_decode :: proc(encoded: string) -> (string, bool) {
    if len(encoded)%2 != 0 {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for i := 0; i < len(encoded); i += 2 {
        high, high_ok := repl_debug_hex_nibble(encoded[i])
        low, low_ok := repl_debug_hex_nibble(encoded[i+1])
        if !high_ok || !low_ok {
            return "", false
        }
        strings.write_byte(&builder, (high << 4) | low)
    }
    return strings.clone(strings.to_string(builder)), true
}

repl_debug_locals_parse :: proc(payload: string) -> (
    locals: [dynamic]Repl_Debug_Local,
    ok: bool,
) {
    if payload == "" {
        return locals, true
    }
    records := strings.split(payload, ",", context.allocator)
    defer delete(records)
    for record in records {
        if record == "" {
            continue
        }
        fields := strings.split(record, ":", context.allocator)
        if len(fields) < 4 || len(fields) > 10 {
            delete(fields)
            for &local in locals {
                repl_debug_local_delete(&local)
            }
            delete(locals)
            return nil, false
        }
        name, name_ok := repl_debug_hex_decode(fields[0])
        ty, ty_ok := repl_debug_hex_decode(fields[1])
        mutable := fields[2] == "1"
        ownership_valid :=
            fields[3] == "value" ||
            fields[3] == "borrowed" ||
            fields[3] == "owned"
        if !name_ok || !ty_ok ||
           (fields[2] != "0" && fields[2] != "1") ||
           !ownership_valid {
            delete(name)
            delete(ty)
            delete(fields)
            for &local in locals {
                repl_debug_local_delete(&local)
            }
            delete(locals)
            return nil, false
        }
        local := Repl_Debug_Local{
            name = name,
            ty = ty,
            mutable = mutable,
            ownership = strings.clone(fields[3]),
            lifecycle =
                repl_type_lifecycle(ty, "", fields[3]),
        }
        paths_ok := true
        if len(fields) >= 5 && fields[4] != "" {
            path_records :=
                strings.split(fields[4], ";", context.allocator)
            for path_record in path_records {
                if path_record == "" {
                    continue
                }
                path_fields :=
                    strings.split(path_record, "=", context.allocator)
                if len(path_fields) != 2 {
                    delete(path_fields)
                    paths_ok = false
                    break
                }
                path, path_ok := repl_debug_hex_decode(path_fields[0])
                path_ty, path_ty_ok :=
                    repl_debug_hex_decode(path_fields[1])
                delete(path_fields)
                if !path_ok || !path_ty_ok {
                    delete(path)
                    delete(path_ty)
                    paths_ok = false
                    break
                }
                append(&local.paths, Repl_Debug_Path{
                    path = path,
                    ty = path_ty,
                })
            }
            delete(path_records)
        }
        if len(fields) >= 6 && fields[5] != "" {
            element_type, element_type_ok :=
                repl_debug_hex_decode(fields[5])
            if !element_type_ok {
                delete(element_type)
                paths_ok = false
            } else {
                local.element_type = element_type
            }
        }
        if len(fields) >= 7 && fields[6] != "" {
            element_path_records :=
                strings.split(fields[6], ";", context.allocator)
            for path_record in element_path_records {
                if path_record == "" {
                    continue
                }
                path_fields :=
                    strings.split(path_record, "=", context.allocator)
                if len(path_fields) != 2 {
                    delete(path_fields)
                    paths_ok = false
                    break
                }
                path, path_ok := repl_debug_hex_decode(path_fields[0])
                path_ty, path_ty_ok :=
                    repl_debug_hex_decode(path_fields[1])
                delete(path_fields)
                if !path_ok || !path_ty_ok {
                    delete(path)
                    delete(path_ty)
                    paths_ok = false
                    break
                }
                append(&local.element_paths, Repl_Debug_Path{
                    path = path,
                    ty = path_ty,
                })
            }
            delete(element_path_records)
        }
        if len(fields) >= 8 && fields[7] != "" {
            key_type, key_type_ok :=
                repl_debug_hex_decode(fields[7])
            if !key_type_ok {
                delete(key_type)
                paths_ok = false
            } else {
                local.key_type = key_type
            }
        }
        if len(fields) >= 9 && fields[8] != "" {
            value_type, value_type_ok :=
                repl_debug_hex_decode(fields[8])
            if !value_type_ok {
                delete(value_type)
                paths_ok = false
            } else {
                local.value_type = value_type
            }
        }
        if len(fields) >= 10 && fields[9] != "" {
            value_path_records :=
                strings.split(fields[9], ";", context.allocator)
            for path_record in value_path_records {
                if path_record == "" {
                    continue
                }
                path_fields :=
                    strings.split(path_record, "=", context.allocator)
                if len(path_fields) != 2 {
                    delete(path_fields)
                    paths_ok = false
                    break
                }
                path, path_ok := repl_debug_hex_decode(path_fields[0])
                path_ty, path_ty_ok :=
                    repl_debug_hex_decode(path_fields[1])
                delete(path_fields)
                if !path_ok || !path_ty_ok {
                    delete(path)
                    delete(path_ty)
                    paths_ok = false
                    break
                }
                append(&local.map_value_paths, Repl_Debug_Path{
                    path = path,
                    ty = path_ty,
                })
            }
            delete(value_path_records)
        }
        delete(fields)
        if !paths_ok {
            repl_debug_local_delete(&local)
            for &retained_local in locals {
                repl_debug_local_delete(&retained_local)
            }
            delete(locals)
            return nil, false
        }
        append(&locals, local)
    }
    return locals, true
}

repl_instrument_nested_pause_points :: proc(
    generated_source,
    input_source,
    input_source_path,
    eval_source,
    eval_source_path: string,
    eval_start_line,
    eval_start_column,
    generation: int,
) -> (
    source: string,
    frames: [dynamic]Repl_Debug_Frame,
    ok: bool,
) {
    input_lines := repl_source_line_index(input_source)
    defer delete(input_lines.starts)
    eval_lines := repl_source_line_index(eval_source)
    defer delete(eval_lines.starts)
    seen_pause_ids := make(map[string]bool, context.temp_allocator)
    prefix := "__KVIST_DEBUG_PAUSE_"
    suffix := "__"
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    cursor := 0
    for cursor < len(generated_source) {
        relative := strings.index(generated_source[cursor:], prefix)
        if relative < 0 {
            strings.write_string(&builder, generated_source[cursor:])
            break
        }
        marker_start := cursor+relative
        strings.write_string(&builder, generated_source[cursor:marker_start])
        body_start := marker_start+len(prefix)
        body_end_relative :=
            strings.index(generated_source[body_start:], suffix)
        if body_end_relative < 0 {
            repl_debug_frames_delete(&frames)
            return "", nil, false
        }
        body_end := body_start+body_end_relative
        source_separator :=
            strings.index(generated_source[body_start:body_end], "_")
        if source_separator <= 0 {
            repl_debug_frames_delete(&frames)
            return "", nil, false
        }
        source_separator += body_start
        source_kind := generated_source[body_start:source_separator]
        start_begin := source_separator+1
        separator :=
            strings.index(generated_source[start_begin:body_end], "_")
        if separator <= 0 || (source_kind != "F" && source_kind != "E") {
            repl_debug_frames_delete(&frames)
            return "", nil, false
        }
        separator += start_begin
        span_start, start_ok :=
            strconv.parse_int(generated_source[start_begin:separator])
        metadata_separator_relative :=
            strings.index(generated_source[separator+1:body_end], "_L")
        span_end_text_end := body_end
        locals_payload := ""
        if metadata_separator_relative >= 0 {
            metadata_separator := separator+1+metadata_separator_relative
            span_end_text_end = metadata_separator
            locals_payload = generated_source[metadata_separator+2:body_end]
        }
        span_end, end_ok :=
            strconv.parse_int(generated_source[separator+1:span_end_text_end])
        if !start_ok || !end_ok {
            repl_debug_frames_delete(&frames)
            return "", nil, false
        }
        locals, locals_ok := repl_debug_locals_parse(locals_payload)
        if !locals_ok {
            repl_debug_frames_delete(&frames)
            return "", nil, false
        }
        pause_id :=
            fmt.tprintf(
                "pause-%d-%d-%d",
                generation,
                span_start,
                span_end,
            )
        strings.write_string(&builder, pause_id)
        already_recorded := seen_pause_ids[pause_id]
        if !already_recorded {
            seen_pause_ids[pause_id] = true
            position_path := eval_source_path
            position_start_line := eval_start_line
            position_start_column := eval_start_column
            if source_kind == "F" {
                position_path = input_source_path
                position_start_line = 1
                position_start_column = 1
            }
            position_index := &eval_lines
            if source_kind == "F" {
                position_index = &input_lines
            }
            local_line, local_column, _, _ :=
                repl_indexed_source_position(position_index, span_start)
            source_line := max(position_start_line, 1)+local_line-1
            source_column := local_column
            if local_line == 1 {
                source_column += max(position_start_column, 1)-1
            }
            append(&frames, Repl_Debug_Frame{
                frame_id =
                    strings.clone(fmt.tprintf("frame-%s", pause_id)),
                pause_id = strings.clone(pause_id),
                generation = generation,
                source_path = strings.clone(position_path),
                line = source_line,
                column = source_column,
                phase = strings.clone("before-form"),
                locals = locals,
            })
        } else {
            for &local in locals {
                repl_debug_local_delete(&local)
            }
            delete(locals)
        }
        cursor = body_end+len(suffix)
    }
    return strings.clone(strings.to_string(builder)), frames, true
}

Repl_Source_Line_Index :: struct {
    source: string,
    starts: [dynamic]int,
}

repl_source_line_index :: proc(source: string) -> Repl_Source_Line_Index {
    index := Repl_Source_Line_Index{source = source}
    append(&index.starts, 0)
    for ch, offset in source {
        if ch == '\n' && offset+1 <= len(source) {
            append(&index.starts, offset+1)
        }
    }
    return index
}

repl_indexed_source_position :: proc(
    index: ^Repl_Source_Line_Index,
    pos: int,
) -> (line, column, line_start, line_end: int) {
    clamped := clamp(pos, 0, len(index.source))
    low := 0
    high := len(index.starts)
    for low < high {
        middle := low+(high-low)/2
        if index.starts[middle] <= clamped {
            low = middle+1
        } else {
            high = middle
        }
    }
    line_index := max(low-1, 0)
    line_start = index.starts[line_index]
    line = line_index+1
    column = clamped-line_start+1
    if line_index+1 < len(index.starts) {
        line_end = index.starts[line_index+1]-1
    } else {
        line_end = len(index.source)
    }
    return
}

repl_generation_breakpoint_locations :: proc(
    entries: []kvist.Source_Map_Entry,
    input,
    input_source,
    eval_source,
    eval_source_path,
    generated_path: string,
    eval_start_line,
    eval_start_column,
    generation: int,
) -> [dynamic]Repl_Breakpoint_Location {
    locations: [dynamic]Repl_Breakpoint_Location
    input_lines := repl_source_line_index(input_source)
    defer delete(input_lines.starts)
    eval_lines := repl_source_line_index(eval_source)
    defer delete(eval_lines.starts)
    for entry in entries {
        source_path := input
        line_offset := 0
        first_line_column_offset := 0
        use_eval_source := false
        if entry.source_span.source == .Eval ||
           (eval_source_path != "" && entry.source_path == "") {
            use_eval_source = true
            source_path =
                eval_source_path if eval_source_path != "" else input
            line_offset = max(eval_start_line, 1)-1
            first_line_column_offset = max(eval_start_column, 1)-1
        } else if entry.source_path != "" && entry.source_path != input {
            // Dependency maps need their own source text. They remain available
            // through the sidecar map, but are not candidates for this
            // submission's source-level breakpoint request.
            continue
        }
        source_lines := &input_lines
        if use_eval_source {
            source_lines = &eval_lines
        }
        start_line, start_column, _, _ :=
            repl_indexed_source_position(
                source_lines,
                entry.source_span.start,
            )
        end_line, end_column, _, _ :=
            repl_indexed_source_position(
                source_lines,
                entry.source_span.end,
            )
        start_line += line_offset
        end_line += line_offset
        if entry.source_span.source == .Eval ||
           (eval_source_path != "" && entry.source_path == "") {
            if start_line == eval_start_line {
                start_column += first_line_column_offset
            }
            if end_line == eval_start_line {
                end_column += first_line_column_offset
            }
        }
        append(&locations, Repl_Breakpoint_Location{
            generation = generation,
            source_path = strings.clone(source_path),
            source_start_line = start_line,
            source_start_column = start_column,
            source_end_line = end_line,
            source_end_column = end_column,
            generated_path = strings.clone(generated_path),
            generated_start_line = entry.generated_start_line,
            generated_start_column = entry.generated_start_column,
            generated_end_line = entry.generated_end_line,
            generated_end_column = entry.generated_end_column,
        })
    }
    return locations
}

repl_inject_pause_before_entry :: proc(
    source,
    pause_id: string,
    source_map: ^[dynamic]kvist.Source_Map_Entry,
) -> (string, bool) {
    needle := "    kvist_repl_host = host\n"
    offset := strings.index(source, needle)
    if offset < 0 {
        return "", false
    }
    insertion_offset := offset+len(needle)
    insertion_line := 1
    for ch in source[:insertion_offset] {
        if ch == '\n' {
            insertion_line += 1
        }
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, source[:insertion_offset])
    fmt.sbprintf(
        &builder,
        "    host.pause(host.ctx, %q, nil, 0, nil, 0, true, nil)\n    if host.abort_requested(host.ctx) %c return %c\n",
        pause_id,
        '{',
        '}',
    )
    strings.write_string(&builder, source[insertion_offset:])
    for &entry in source_map {
        if entry.generated_start_line >= insertion_line {
            entry.generated_start_line += 2
        }
        if entry.generated_end_line >= insertion_line {
            entry.generated_end_line += 2
        }
    }
    return strings.clone(strings.to_string(builder)), true
}

Repl_Thin_Odin_Decl :: struct {
    name:       string,
    start_line: int,
    end_line:   int,
}

repl_thin_scalar_abi :: proc(abi: string) -> bool {
    if !strings.has_prefix(abi, "value:") {
        return false
    }
    switch abi[len("value:"):] {
    case "bool", "int", "i8", "i16", "i32", "i64", "i128",
         "uint", "u8", "u16", "u32", "u64", "u128", "uintptr",
         "f32", "f64", "string":
        return true
    }
    return false
}

repl_latest_generation_dependencies_valid :: proc(
    session: ^Repl_Session,
) -> bool {
    if session == nil || len(session.compiled_generations) == 0 {
        return false
    }
    latest := &session.compiled_generations[len(session.compiled_generations)-1]
    for record in latest.dependency_files {
        if !file_fingerprint_matches_metadata(record) {
            return false
        }
    }
    for record in latest.dependency_directories {
        if !directory_fingerprint_matches_metadata(record) {
            return false
        }
    }
    return true
}

repl_is_resident_direct_command :: proc(value: string) -> bool {
    return strings.has_prefix(value, REPL_WORKER_EXECUTION_PLAN_PREFIX) ||
           strings.has_prefix(value, REPL_WORKER_DIRECT_INT_PREFIX) ||
           strings.has_prefix(value, REPL_WORKER_DIRECT_SCALAR_PREFIX)
}

repl_is_direct_worker_command :: proc(value: string) -> bool {
    return repl_is_resident_direct_command(value) ||
           strings.has_prefix(
               value,
               kvist_repl.WORKER_INCREMENTAL_PROGRAM_PREFIX,
           ) ||
           strings.has_prefix(value, REPL_WORKER_LOADED_NATIVE_PREFIX)
}

repl_loaded_native_command :: proc(path: string) -> string {
    encoded_path := repl_debug_hex_encode(path)
    defer delete(encoded_path)
    return strings.clone(
        fmt.tprintf(
            "%s%s",
            REPL_WORKER_LOADED_NATIVE_PREFIX,
            encoded_path,
        ),
    )
}

repl_execution_plan_command :: proc(
    plan: kvist.Repl_Execution_Plan,
) -> (command, emitted_source: string, ok: bool) {
    if plan.encoded == "" || plan.result_abi == "" {
        return "", "", false
    }
    emitted_source = ""
    if !plan.preserves_result_history {
        emitted_source =
            strings.clone(
                fmt.tprintf(
                    "host.register_result(host.ctx, %q, nil)",
                    plan.result_abi,
                ),
            )
    }
    return strings.clone(
               fmt.tprintf(
                   "%s%s",
                   REPL_WORKER_EXECUTION_PLAN_PREFIX,
                   plan.encoded,
               ),
           ),
           emitted_source,
           true
}

repl_incremental_program_command :: proc(
    program: kvist.Repl_Incremental_Program,
) -> (string, bool) {
    if program.encoded == "" {
        return "", false
    }
    return strings.clone(
        fmt.tprintf(
            "%s%s",
            kvist_repl.WORKER_INCREMENTAL_PROGRAM_PREFIX,
            program.encoded,
        ),
    ), true
}

repl_session_clear_resident_scalar_invokes :: proc(session: ^Repl_Session) {
    if session == nil {
        return
    }
    for &invoke in session.resident_scalar_invokes {
        delete(invoke.name)
        delete(invoke.signature)
        delete(invoke.result_abi)
    }
    clear(&session.resident_scalar_invokes)
}

repl_session_replace_scalar_invokes :: proc(session: ^Repl_Session) {
    repl_session_clear_resident_scalar_invokes(session)
    if session == nil {
        return
    }
    // Package dependency refreshes replace the generated package adapters,
    // but already-loaded session procedures remain callable in the worker.
    // Rebuild their metadata from the authoritative active bindings so a
    // package refresh does not strand otherwise valid composed calls.
    for binding in session.bindings {
        if binding.stale || !binding.direct_scalar_invoke ||
           (binding.kind != "defn" && binding.kind != "defn-") ||
           !strings.has_prefix(binding.abi, "proc(") {
            continue
        }
        close := strings.index(binding.abi, ")->")
        if close < len("proc(") {
            continue
        }
        result_ty := repl_scalar_signature_type(
            binding.abi[close+len(")->"):],
        )
        if result_ty != "bool" && result_ty != "int" &&
           result_ty != "f64" && result_ty != "string" &&
           result_ty != "Data" {
            continue
        }
        mapped_name := kvist.map_name(binding.name)
        result_abi := fmt.aprintf("value:%s", result_ty)
        repl_session_upsert_scalar_invoke(
            session,
            mapped_name,
            binding.abi,
            result_abi,
        )
        delete(mapped_name)
        delete(result_abi)
    }
}

repl_quoted_value_at :: proc(
    value: string,
    start: int,
) -> (decoded: string, next: int, ok: bool) {
    if start < 0 || start >= len(value) || value[start] != '"' {
        return "", start, false
    }
    escaped := false
    for end in start+1..<len(value) {
        if escaped {
            escaped = false
            continue
        }
        if value[end] == '\\' {
            escaped = true
            continue
        }
        if value[end] != '"' {
            continue
        }
        parsed, allocated, parsed_ok :=
            strconv.unquote_string(value[start:end+1])
        if !parsed_ok {
            return "", start, false
        }
        decoded = strings.clone(parsed)
        if allocated {
            delete(parsed)
        }
        return decoded, end+1, true
    }
    return "", start, false
}

repl_scalar_registration_from_line :: proc(
    line: string,
) -> (name, signature, result_abi: string, ok: bool) {
    prefix := "host.register_scalar_invoke(host.ctx, "
    offset := strings.index(line, prefix)
    if offset < 0 {
        return
    }
    cursor := offset+len(prefix)
    name, cursor, ok = repl_quoted_value_at(line, cursor)
    if !ok {
        return
    }
    signature_start := strings.index(line[cursor:], "\"")
    if signature_start < 0 {
        delete(name)
        return "", "", "", false
    }
    signature, cursor, ok =
        repl_quoted_value_at(line, cursor+signature_start)
    if !ok {
        delete(name)
        return "", "", "", false
    }
    result_start := strings.index(line[cursor:], "\"")
    if result_start < 0 {
        delete(name)
        delete(signature)
        return "", "", "", false
    }
    result_abi, _, ok = repl_quoted_value_at(line, cursor+result_start)
    if !ok {
        delete(name)
        delete(signature)
        return "", "", "", false
    }
    return name, signature, result_abi, true
}

repl_session_upsert_scalar_invoke :: proc(
    session: ^Repl_Session,
    name,
    signature,
    result_abi: string,
) {
    for &invoke in session.resident_scalar_invokes {
        if invoke.name != name || invoke.signature != signature {
            continue
        }
        delete(invoke.result_abi)
        invoke.result_abi = strings.clone(result_abi)
        return
    }
    append(&session.resident_scalar_invokes, kvist.Repl_Scalar_Invoke_Metadata{
        name = strings.clone(name),
        signature = strings.clone(signature),
        result_abi = strings.clone(result_abi),
    })
}

repl_session_record_scalar_invokes :: proc(
    session: ^Repl_Session,
    generated_source: string,
    replace := false,
) {
    if session == nil {
        return
    }
    if replace {
        repl_session_replace_scalar_invokes(session)
    }
    lines := strings.split_lines(generated_source, context.temp_allocator)
    for line in lines {
        name, signature, result_abi, parsed :=
            repl_scalar_registration_from_line(line)
        if !parsed {
            continue
        }
        repl_session_upsert_scalar_invoke(
            session,
            name,
            signature,
            result_abi,
        )
        delete(name)
        delete(signature)
        delete(result_abi)
    }
}

repl_session_record_incremental_scalar_invokes :: proc(
    session: ^Repl_Session,
    command: string,
    replace := false,
) -> bool {
    if session == nil || !strings.has_prefix(
        command,
        kvist_repl.WORKER_INCREMENTAL_PROGRAM_PREFIX,
    ) {
        return false
    }
    encoded := command[len(kvist_repl.WORKER_INCREMENTAL_PROGRAM_PREFIX):]
    program, decoded := repl_program.program_decode(encoded)
    if !decoded {
        return false
    }
    defer repl_program.program_delete(&program)
    for procedure in program.procedures {
        if procedure.result_kind != .Bool &&
           procedure.result_kind != .Int &&
           procedure.result_kind != .F64 {
            return false
        }
    }
    // An incremental batch publishes only the procedures encoded below; it
    // does not reload or invalidate package/context adapters already present
    // in the worker. Keep those exact registrations available for later
    // incremental callers. Same-name incompatible session signatures are
    // removed explicitly before the new registrations are merged.
    _ = replace
    for procedure in program.procedures {
        for index := len(session.resident_scalar_invokes)-1;
            index >= 0;
            index -= 1 {
            invoke := &session.resident_scalar_invokes[index]
            if invoke.name != procedure.name ||
               invoke.signature == procedure.signature {
                continue
            }
            delete(invoke.name)
            delete(invoke.signature)
            delete(invoke.result_abi)
            unordered_remove(&session.resident_scalar_invokes, index)
        }
    }
    for procedure in program.procedures {
        result_type := ""
        switch procedure.result_kind {
        case .Bool: result_type = "bool"
        case .Int:  result_type = "int"
        case .F64:  result_type = "f64"
        case .Invalid, .Void, .String, .Data:
        }
        result_abi := fmt.aprintf("value:%s", result_type)
        repl_session_upsert_scalar_invoke(
            session,
            procedure.name,
            procedure.signature,
            result_abi,
        )
        delete(result_abi)
    }
    return true
}

repl_session_record_generation_scalar_invokes :: proc(
    session: ^Repl_Session,
    generated_source_path: string,
    replace := false,
) {
    if replace {
        repl_session_replace_scalar_invokes(session)
    }
    generated_source, read_err := os.read_entire_file_from_path(
        generated_source_path,
        context.allocator,
    )
    if read_err != nil {
        return
    }
    defer delete(generated_source)
    repl_session_record_scalar_invokes(
        session,
        string(generated_source),
    )
}

repl_direct_mapped_name :: proc(name: string) -> string {
    separator := strings.index(name, ".")
    if separator <= 0 || separator+1 >= len(name) {
        return kvist.map_name(name)
    }
    alias := kvist.map_name(name[:separator])
    defer delete(alias)
    member := kvist.map_name(name[separator+1:])
    defer delete(member)
    return strings.clone(fmt.tprintf("%s__%s", alias, member))
}

repl_registered_scalar_invoke_abi :: proc(
    emitted_source,
    logical_name: string,
) -> string {
    mapped := repl_direct_mapped_name(logical_name)
    defer delete(mapped)
    needle := fmt.tprintf(
        "host.register_scalar_invoke(host.ctx, %q, ",
        mapped,
    )
    offset := strings.index(emitted_source, needle)
    if offset < 0 {
        return ""
    }
    rest := emitted_source[offset+len(needle):]
    if rest == "" || rest[0] != '"' {
        return ""
    }
    escaped := false
    for index in 1..<len(rest) {
        if escaped {
            escaped = false
        } else if rest[index] == '\\' {
            escaped = true
        } else if rest[index] == '"' {
            return strings.clone(rest[1:index])
        }
    }
    return ""
}

repl_scalar_signature_type :: proc(value: string) -> string {
    separator := strings.index(value, ":")
    if separator >= 0 {
        return strings.trim_space(value[:separator])
    }
    return strings.trim_space(value)
}

repl_direct_scalar_invocation :: proc(
    source,
    emitted_source: string,
) -> (string, bool) {
    form, _, parsed := kvist.read_single_eval_form(source)
    if !parsed {
        return "", false
    }
    defer kvist.delete_borrowed_cst_form(&form)
    if form.kind != .List || len(form.items) == 0 ||
       len(form.items) > 5 || form.items[0].kind != .Symbol {
        return "", false
    }
    name := form.items[0].text
    signature := repl_registered_scalar_invoke_abi(emitted_source, name)
    defer delete(signature)
    if !strings.has_prefix(signature, "proc(") {
        return "", false
    }
    close := strings.index(signature, ")->")
    if close < len("proc(") {
        return "", false
    }
    params_text := signature[len("proc("):close]
    return_text := repl_scalar_signature_type(signature[close+len(")->"):])
    if return_text != "bool" && return_text != "int" &&
       return_text != "f64" && return_text != "string" &&
       return_text != "Data" {
        return "", false
    }
    params: []string
    if strings.trim_space(params_text) != "" {
        params = strings.split(params_text, ",", context.temp_allocator)
    }
    if len(params) != len(form.items)-1 {
        return "", false
    }
    mapped_name := repl_direct_mapped_name(name)
    defer delete(mapped_name)
    result_line_offset := strings.last_index(
        emitted_source,
        "kvist_repl_result_value := ",
    )
    if result_line_offset < 0 {
        return "", false
    }
    result_line := emitted_source[result_line_offset:]
    if newline := strings.index(result_line, "\n"); newline >= 0 {
        result_line = result_line[:newline]
    }
    if !strings.contains(result_line, fmt.tprintf("%s(", mapped_name)) {
        return "", false
    }
    encoded_name := repl_debug_hex_encode(mapped_name)
    defer delete(encoded_name)
    encoded_signature := repl_debug_hex_encode(signature)
    defer delete(encoded_signature)
    command := strings.builder_make()
    defer strings.builder_destroy(&command)
    fmt.sbprintf(
        &command,
        "%s%s\t%s",
        REPL_WORKER_DIRECT_SCALAR_PREFIX,
        encoded_name,
        encoded_signature,
    )
    for arg, index in form.items[1:] {
        ty := repl_scalar_signature_type(params[index])
        switch ty {
        case "bool":
            if arg.kind != .Bool {
                return "", false
            }
            fmt.sbprintf(&command, "\tb:%s", "1" if arg.text == "true" else "0")
        case "int":
            if arg.kind != .Number {
                return "", false
            }
            value, ok := strconv.parse_int(arg.text)
            if !ok {
                return "", false
            }
            fmt.sbprintf(&command, "\ti:%d", value)
        case "f64":
            if arg.kind != .Number {
                return "", false
            }
            value, ok := strconv.parse_f64(arg.text)
            if !ok {
                return "", false
            }
            fmt.sbprintf(&command, "\tf:%.17g", value)
        case "string":
            if arg.kind != .String {
                return "", false
            }
            value, allocated, ok := strconv.unquote_string(arg.text)
            if !ok {
                return "", false
            }
            encoded := repl_debug_hex_encode(value)
            if allocated {
                delete(value)
            }
            fmt.sbprintf(&command, "\ts:%s", encoded)
            delete(encoded)
        case "Data":
            if arg.kind != .Symbol ||
               (arg.text != "*1" && arg.text != "*2" && arg.text != "*3") {
                return "", false
            }
            mapped_result := kvist.map_name(
                fmt.tprintf("kvist_repl_star_%s", arg.text[1:]),
            )
            encoded := repl_debug_hex_encode(mapped_result)
            fmt.sbprintf(&command, "\tr:%s", encoded)
            delete(encoded)
            delete(mapped_result)
        case:
            return "", false
        }
    }
    return strings.clone(strings.to_string(command)), true
}

repl_resident_scalar_invocation :: proc(
    source: string,
    session: ^Repl_Session,
) -> (command, emitted_source: string, ok: bool) {
    if session == nil {
        return "", "", false
    }
    form, _, parsed := kvist.read_single_eval_form(source)
    if !parsed {
        return "", "", false
    }
    defer kvist.delete_borrowed_cst_form(&form)
    if form.kind != .List || len(form.items) == 0 ||
       form.items[0].kind != .Symbol {
        return "", "", false
    }
    name := form.items[0].text
    binding_index, found := repl_binding_index(session, name)
    mapped_name := repl_direct_mapped_name(name)
    defer delete(mapped_name)
    if !found {
        matched_command := ""
        matched_result := ""
        matches := 0
        for invoke in session.resident_scalar_invokes {
            if invoke.name != mapped_name ||
               !strings.has_prefix(invoke.signature, "proc(") {
                continue
            }
            synthetic := fmt.tprintf(
                "host.register_scalar_invoke(host.ctx, %q, %q, nil)\nkvist_repl_result_value := %s(",
                mapped_name,
                invoke.signature,
                mapped_name,
            )
            candidate, candidate_ok :=
                repl_direct_scalar_invocation(source, synthetic)
            if !candidate_ok {
                continue
            }
            matches += 1
            if matches == 1 {
                matched_command = candidate
                matched_result = strings.clone(
                    fmt.tprintf(
                        "host.register_result(host.ctx, %q, nil)",
                        invoke.result_abi,
                    ),
                )
            } else {
                delete(candidate)
                delete(matched_command)
                delete(matched_result)
                return "", "", false
            }
        }
        if matches == 1 {
            return matched_command, matched_result, true
        }
        return "", "", false
    }
    binding := &session.bindings[binding_index]
    if binding.stale ||
       !binding.direct_scalar_invoke ||
       (binding.kind != "defn" && binding.kind != "defn-") {
        return "", "", false
    }
    signature := binding.abi
    if !strings.has_prefix(signature, "proc(") {
        return "", "", false
    }
    close := strings.index(signature, ")->")
    if close < len("proc(") {
        return "", "", false
    }
    synthetic := fmt.tprintf(
        "host.register_scalar_invoke(host.ctx, %q, %q, nil)\nkvist_repl_result_value := %s(",
        mapped_name,
        signature,
        mapped_name,
    )
    direct, direct_ok := repl_direct_scalar_invocation(source, synthetic)
    if !direct_ok {
        return "", "", false
    }
    result_ty := repl_scalar_signature_type(signature[close+len(")->"):])
    result_abi := fmt.tprintf("value:%s", result_ty)
    result_source := strings.clone(
        fmt.tprintf(
            "host.register_result(host.ctx, %q, nil)",
            result_abi,
        ),
    )
    return direct, result_source, true
}

repl_direct_int_invocation :: proc(
    source,
    emitted_source: string,
) -> (string, bool) {
    form := strings.trim_space(source)
    if len(form) < 3 || form[0] != '(' || form[len(form)-1] != ')' {
        return "", false
    }
    body := strings.trim_space(form[1:len(form)-1])
    if body == "" || strings.contains(body, "\n") ||
       strings.contains(body, "\r") {
        return "", false
    }
    fields := strings.fields(body, context.temp_allocator)
    if len(fields) == 0 || len(fields) > 5 {
        return "", false
    }
    name := fields[0]
    if !kvist.odin_identifier_start(name[0]) {
        return "", false
    }
    for ch in name {
        if !kvist.odin_identifier_continue(u8(ch)) &&
           ch != '-' && ch != '!' && ch != '?' {
            return "", false
        }
    }
    args: [4]int
    for field, index in fields[1:] {
        value, parsed := strconv.parse_int(field)
        if !parsed {
            return "", false
        }
        args[index] = value
    }
    signature := kvist.repl_registered_abi(emitted_source, name)
    defer delete(signature)
    expected := strings.builder_make()
    defer strings.builder_destroy(&expected)
    strings.write_string(&expected, "proc(")
    for index in 0..<len(fields)-1 {
        if index > 0 {
            strings.write_byte(&expected, ',')
        }
        strings.write_string(&expected, "int:borrowed")
    }
    strings.write_string(&expected, ")->int")
    if signature != strings.to_string(expected) {
        return "", false
    }
    mapped_name := kvist.map_name(name)
    defer delete(mapped_name)
    expression_needle := fmt.tprintf(
        "kvist_repl_result_value := %s(",
        mapped_name,
    )
    if !strings.contains(emitted_source, expression_needle) {
        return "", false
    }
    encoded_name := repl_debug_hex_encode(mapped_name)
    defer delete(encoded_name)
    encoded_signature := repl_debug_hex_encode(signature)
    defer delete(encoded_signature)
    command := strings.builder_make()
    defer strings.builder_destroy(&command)
    fmt.sbprintf(
        &command,
        "%s%s\t%s",
        REPL_WORKER_DIRECT_INT_PREFIX,
        encoded_name,
        encoded_signature,
    )
    for arg in args[:len(fields)-1] {
        fmt.sbprintf(&command, "\t%d", arg)
    }
    return strings.clone(strings.to_string(command)), true
}

repl_odin_line_decl_name :: proc(line: string) -> (string, bool) {
    if line == "" || !kvist.odin_identifier_start(line[0]) {
        return "", false
    }
    end := 1
    for end < len(line) && kvist.odin_identifier_continue(line[end]) {
        end += 1
    }
    rest := strings.trim_space(line[end:])
    if !strings.has_prefix(rest, "::") &&
       !strings.has_prefix(rest, ":") {
        return "", false
    }
    return line[:end], true
}

repl_odin_import_alias :: proc(line: string) -> (string, bool) {
    if !strings.has_prefix(line, "import ") {
        return "", false
    }
    rest := strings.trim_space(line[len("import "):])
    if rest == "" || rest[0] == '"' ||
       !kvist.odin_identifier_start(rest[0]) {
        return "", false
    }
    end := 1
    for end < len(rest) && kvist.odin_identifier_continue(rest[end]) {
        end += 1
    }
    return rest[:end], true
}

repl_thin_adjust_source_map :: proc(
    source_map: ^[dynamic]kvist.Source_Map_Entry,
    retained: []bool,
) {
    if source_map == nil || len(retained) == 0 {
        return
    }
    line_count := len(retained)
    mapped_lines := make([]int, line_count, context.temp_allocator)
    next_retained := make([]int, line_count, context.temp_allocator)
    previous_retained := make([]int, line_count, context.temp_allocator)
    mapped := 0
    previous := -1
    for line in 0..<line_count {
        if retained[line] {
            mapped += 1
            previous = line
            mapped_lines[line] = mapped
        }
        previous_retained[line] = previous
    }
    next := -1
    for line := line_count-1; line >= 0; line -= 1 {
        if retained[line] {
            next = line
        }
        next_retained[line] = next
    }
    write := 0
    for read in 0..<len(source_map^) {
        entry := source_map^[read]
        start := clamp(entry.generated_start_line-1, 0, line_count-1)
        end := clamp(entry.generated_end_line-1, start, line_count-1)
        first := next_retained[start]
        last := previous_retained[end]
        if first < 0 || first > end || last < first {
            delete(entry.source_path)
            source_map^[read] = {}
            continue
        }
        entry.generated_start_line = mapped_lines[first]
        entry.generated_end_line = mapped_lines[last]
        if first != start {
            entry.generated_start_column = 0
        }
        if last != end {
            entry.generated_end_column = 0
        }
        source_map^[write] = entry
        if write != read {
            source_map^[read] = {}
        }
        write += 1
    }
    resize(source_map, write)
}

repl_thin_filter_debug_frames :: proc(
    frames: ^[dynamic]Repl_Debug_Frame,
    source: string,
) {
    if frames == nil {
        return
    }
    write := 0
    for read in 0..<len(frames^) {
        frame := frames^[read]
        if frame.pause_id == "" ||
           !strings.contains(source, frame.pause_id) {
            repl_debug_frame_delete(&frame)
            frames^[read] = {}
            continue
        }
        frames^[write] = frame
        if write != read {
            frames^[read] = {}
        }
        write += 1
    }
    resize(frames, write)
}

repl_thin_enqueue_decl :: proc(
    name: string,
    names: map[string]int,
    reachable: []bool,
    queue: ^[dynamic]int,
) {
    index, found := names[name]
    if !found || reachable[index] {
        return
    }
    reachable[index] = true
    append(queue, index)
}

repl_thin_enqueue_line_decls :: proc(
    line: string,
    names: map[string]int,
    reachable: []bool,
    queue: ^[dynamic]int,
) {
    position := 0
    for position < len(line) {
        if !kvist.odin_identifier_start(line[position]) {
            position += 1
            continue
        }
        end := position+1
        for end < len(line) &&
            kvist.odin_identifier_continue(line[end]) {
            end += 1
        }
        repl_thin_enqueue_decl(
            line[position:end],
            names,
            reachable,
            queue,
        )
        position = end
    }
}

repl_thin_generation_source :: proc(
    source: string,
    source_map: ^[dynamic]kvist.Source_Map_Entry,
    debug_frames: ^[dynamic]Repl_Debug_Frame = nil,
) -> string {
    lines := strings.split_lines(source, context.temp_allocator)
    if len(lines) == 0 {
        return strings.clone(source)
    }
    declarations: [dynamic]Repl_Thin_Odin_Decl
    defer delete(declarations)
    names := make(map[string]int, context.temp_allocator)
    for line, line_index in lines {
        name, named := repl_odin_line_decl_name(line)
        if !named {
            continue
        }
        if len(declarations) > 0 {
            declarations[len(declarations)-1].end_line = line_index
        }
        names[name] = len(declarations)
        append(&declarations, Repl_Thin_Odin_Decl{
            name = name,
            start_line = line_index,
            end_line = len(lines),
        })
    }
    if len(declarations) == 0 {
        return strings.clone(source)
    }
    reachable := make([]bool, len(declarations), context.temp_allocator)
    queue: [dynamic]int
    defer delete(queue)
    context_procs_start, context_procs_end := -1, -1
    for line, line_index in lines {
        if strings.contains(line, "KVIST_REPL_CONTEXT_PROCS_BEGIN") {
            context_procs_start = line_index
        } else if strings.contains(line, "KVIST_REPL_CONTEXT_PROCS_END") {
            context_procs_end = line_index
        }
    }
    repl_thin_enqueue_decl(
        "kvist_repl_api_version",
        names,
        reachable,
        &queue,
    )
    repl_thin_enqueue_decl("kvist_repl_run", names, reachable, &queue)
    for decl, index in declarations {
        directive_line := decl.start_line-1
        for directive_line >= 0 &&
            strings.trim_space(lines[directive_line]) == "" {
            directive_line -= 1
        }
        if directive_line >= 0 {
            directive := strings.trim_space(lines[directive_line])
            if strings.has_prefix(directive, "@(init") ||
               strings.has_prefix(directive, "@(fini") ||
               strings.has_prefix(directive, "@(export") {
                if !reachable[index] {
                    reachable[index] = true
                    append(&queue, index)
                }
            }
        }
    }
    queue_index := 0
    for queue_index < len(queue) {
        decl := declarations[queue[queue_index]]
        for line_index in decl.start_line..<decl.end_line {
            if context_procs_start >= 0 && context_procs_end >= 0 &&
               line_index >= context_procs_start &&
               line_index <= context_procs_end {
                continue
            }
            repl_thin_enqueue_line_decls(
                lines[line_index],
                names,
                reachable,
                &queue,
            )
        }
        queue_index += 1
    }
    context_registration_lines :=
        make([]bool, len(lines), context.temp_allocator)
    if context_procs_start >= 0 && context_procs_end > context_procs_start {
        for line_index in context_procs_start+1..<context_procs_end {
            line := lines[line_index]
            registered_name := ""
            owned_name := ""
            if name, signature, result_abi, scalar :=
                repl_scalar_registration_from_line(line); scalar {
                owned_name = name
                registered_name = owned_name
                delete(signature)
                delete(result_abi)
            } else {
                prefix := "host.register_proc(host.ctx, "
                if offset := strings.index(line, prefix); offset >= 0 {
                    name, _, parsed := repl_quoted_value_at(
                        line,
                        offset+len(prefix),
                    )
                    if parsed {
                        owned_name = name
                        registered_name = owned_name
                    }
                }
            }
            if registered_name != "" {
                if decl_index, found := names[registered_name]; found &&
                   reachable[decl_index] {
                    context_registration_lines[line_index] = true
                    repl_thin_enqueue_line_decls(
                        line,
                        names,
                        reachable,
                        &queue,
                    )
                }
            }
            delete(owned_name)
        }
    }
    for queue_index < len(queue) {
        decl := declarations[queue[queue_index]]
        for line_index in decl.start_line..<decl.end_line {
            if context_procs_start >= 0 && context_procs_end >= 0 &&
               line_index >= context_procs_start &&
               line_index <= context_procs_end {
                continue
            }
            repl_thin_enqueue_line_decls(
                lines[line_index],
                names,
                reachable,
                &queue,
            )
        }
        queue_index += 1
    }
    retained := make([]bool, len(lines), context.temp_allocator)
    for line_index in 0..<len(lines) {
        retained[line_index] = true
    }
    for decl, index in declarations {
        if reachable[index] {
            continue
        }
        for line_index in decl.start_line..<decl.end_line {
            retained[line_index] = false
        }
    }
    if context_procs_start >= 0 && context_procs_end >= context_procs_start {
        for line_index in context_procs_start..=context_procs_end {
            retained[line_index] = context_registration_lines[line_index]
        }
    }
    for decl, index in declarations {
        if !reachable[index] {
            continue
        }
        directive_line := decl.start_line-1
        for directive_line >= 0 &&
            strings.trim_space(lines[directive_line]) == "" {
            directive_line -= 1
        }
        if directive_line >= 0 &&
           strings.has_prefix(strings.trim_space(lines[directive_line]), "@(") {
            retained[directive_line] = true
        }
    }
    condition_runtime_needed := false
    for decl, index in declarations {
        if reachable[index] && strings.contains(decl.name, "condition__") {
            condition_runtime_needed = true
            break
        }
    }
    if !condition_runtime_needed {
        for line, line_index in lines {
            if retained[line_index] &&
               strings.contains(line, ".set_repl_host(") {
                retained[line_index] = false
            }
        }
    }
    for line, line_index in lines {
        alias, imported := repl_odin_import_alias(line)
        if !imported {
            continue
        }
        used := false
        needle := fmt.tprintf("%s.", alias)
        for candidate, candidate_index in lines {
            if candidate_index != line_index && retained[candidate_index] &&
               strings.contains(candidate, needle) {
                used = true
                break
            }
        }
        retained[line_index] = used
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for line, line_index in lines {
        if !retained[line_index] {
            continue
        }
        strings.write_string(&builder, line)
        strings.write_byte(&builder, '\n')
    }
    thin := strings.clone(strings.to_string(builder))
    repl_thin_adjust_source_map(source_map, retained)
    repl_thin_filter_debug_frames(debug_frames, thin)
    return thin
}

repl_generation_source_hash :: proc(source: string, generation: int) -> u64 {
    // Nested safe-point IDs carry the controller generation even when the
    // generated program is otherwise identical. Exclude only that component
    // from the fingerprint; the source locations and all executable code
    // remain part of the key.
    prefix := fmt.tprintf("pause-%d-", generation)
    stable_prefix := "pause-generation-"
    case_prefix := "kvist_case_"
    canonical_cases := make(map[string]int, context.temp_allocator)
    next_case := 1
    hash := u64(14695981039346656037)
    start := 0
    i := 0
    for i < len(source) {
        if strings.has_prefix(source[i:], prefix) {
            hash = fnv1a_update(hash, transmute([]byte)source[start:i])
            hash = fnv1a_update(hash, transmute([]byte)stable_prefix)
            i += len(prefix)
            start = i
            continue
        }
        if !strings.has_prefix(source[i:], case_prefix) {
            i += 1
            continue
        }
        digit_start := i + len(case_prefix)
        digit_end := digit_start
        for digit_end < len(source) &&
            source[digit_end] >= '0' && source[digit_end] <= '9' {
            digit_end += 1
        }
        if digit_end == digit_start {
            i += 1
            continue
        }
        hash = fnv1a_update(hash, transmute([]byte)source[start:i])
        name := source[i:digit_end]
        canonical, known := canonical_cases[name]
        if !known {
            canonical = next_case
            canonical_cases[name] = canonical
            next_case += 1
        }
        hash = fnv1a_update(hash, transmute([]byte)case_prefix)
        canonical_text := fmt.tprintf("%d", canonical)
        hash = fnv1a_update(hash, transmute([]byte)canonical_text)
        i = digit_end
        start = digit_end
    }
    return fnv1a_update(hash, transmute([]byte)source[start:])
}

repl_hash_key_string :: proc(hash: u64, value: string) -> u64 {
    length := fmt.tprintf("%d:", len(value))
    result := fnv1a_update(hash, transmute([]byte)length)
    return fnv1a_update(result, transmute([]byte)value)
}

repl_frontend_request_hash :: proc(
    dependency_key,
    source,
    session_source: string,
    no_print: bool,
    recent_result_types: []string,
    stale_proc_names: []string,
    scalar_invokes: []kvist.Repl_Scalar_Invoke_Metadata,
    eval_source_path: string,
    eval_start_line,
    eval_start_column: int,
    inspect_only: bool,
    inspection_source_slot,
    inspection_source_type,
    inspection_result_slot: string,
    inspection_page_offset,
    inspection_page_limit: int,
    capture_debug_values: bool,
    fast_native_build: bool,
) -> (request_hash, resident_request_hash: u64, ok: bool) {
    if dependency_key == "" {
        return 0, 0, false
    }
    hash := u64(14695981039346656037)
    hash = repl_hash_key_string(hash, dependency_key)
    hash = repl_hash_key_string(hash, source)
    hash = repl_hash_key_string(hash, session_source)
    hash = repl_hash_key_string(hash, eval_source_path)
    hash = repl_hash_key_string(hash, fmt.tprintf("%d", eval_start_line))
    hash = repl_hash_key_string(hash, fmt.tprintf("%d", eval_start_column))
    hash = repl_hash_key_string(hash, "1" if no_print else "0")
    hash = repl_hash_key_string(hash, "1" if inspect_only else "0")
    hash = repl_hash_key_string(hash, inspection_source_slot)
    hash = repl_hash_key_string(hash, inspection_source_type)
    hash = repl_hash_key_string(hash, inspection_result_slot)
    hash = repl_hash_key_string(hash, fmt.tprintf("%d", inspection_page_offset))
    hash = repl_hash_key_string(hash, fmt.tprintf("%d", inspection_page_limit))
    hash = repl_hash_key_string(hash, "1" if capture_debug_values else "0")
    hash = repl_hash_key_string(hash, "1" if fast_native_build else "0")
    for name in stale_proc_names {
        hash = repl_hash_key_string(hash, name)
    }
    for invoke in scalar_invokes {
        hash = repl_hash_key_string(hash, invoke.name)
        hash = repl_hash_key_string(hash, invoke.signature)
        hash = repl_hash_key_string(hash, invoke.result_abi)
    }
    resident_request_hash = hash
    for ty in recent_result_types {
        hash = repl_hash_key_string(hash, ty)
    }
    return hash, resident_request_hash, true
}

repl_context_cache_key_with_dependency :: proc(
    dependency_key,
    session_source,
    source: string,
) -> string {
    if dependency_key == "" {
        return ""
    }
    imports := kvist.repl_persistent_imports_source(session_source)
    defer delete(imports)
    current_imports := kvist.repl_persistent_imports_source(source)
    defer delete(current_imports)
    return strings.clone(
        fmt.tprintf(
            "%d:%s%d:%s%d:%s",
            len(dependency_key),
            dependency_key,
            len(imports),
            imports,
            len(current_imports),
            current_imports,
        ),
    )
}

repl_context_cache_key :: proc(input, session_source, source: string) -> string {
    dependency_key, dependency_ok := cached_compile_cache_key(input)
    if !dependency_ok {
        return ""
    }
    defer delete(dependency_key)
    return repl_context_cache_key_with_dependency(
        dependency_key,
        session_source,
        source,
    )
}

repl_native_toolchain_fingerprint :: proc() -> (u64, bool) {
    sync.mutex_guard(&repl_native_toolchain_mutex)
    if repl_native_toolchain_initialized {
        return repl_native_toolchain_hash, repl_native_toolchain_ok
    }
    repl_native_toolchain_initialized = true
    state, stdout, stderr, process_err := os.process_exec(
        os.Process_Desc{command = {"odin", "version"}},
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    if process_err != nil || !state.exited || state.exit_code != 0 {
        return 0, false
    }
    hash := u64(14695981039346656037)
    hash = fnv1a_update(hash, stdout)
    hash = fnv1a_update(hash, stderr)
    odin_root, found := os.lookup_env("ODIN_ROOT", context.allocator)
    if found {
        hash = repl_hash_key_string(hash, odin_root)
        delete(odin_root)
    }
    repl_native_toolchain_hash = hash
    repl_native_toolchain_ok = true
    return hash, true
}

repl_native_artifact_cache_entry :: proc(
    request_hash,
    source_hash: u64,
    fast_native_build: bool,
) -> (string, bool) {
    if compile_cache_disabled() || request_hash == 0 || source_hash == 0 {
        return "", false
    }
    toolchain_hash, toolchain_ok := repl_native_toolchain_fingerprint()
    if !toolchain_ok {
        return "", false
    }
    base := cache_dir_or_exit()
    defer delete(base)
    cache_dir, cache_dir_err := os.join_path(
        {base, "repl-native"},
        context.allocator,
    )
    if cache_dir_err != nil {
        return "", false
    }
    defer delete(cache_dir)
    if !os.exists(cache_dir) && os.make_directory_all(cache_dir) != nil {
        return "", false
    }
    name := fmt.tprintf(
        "v%d-a%d-%016x-%016x-%016x-%d",
        REPL_NATIVE_ARTIFACT_CACHE_VERSION,
        kvist_repl.GENERATION_ABI_VERSION,
        toolchain_hash,
        request_hash,
        source_hash,
        1 if fast_native_build else 0,
    )
    entry, entry_err := os.join_path(
        {cache_dir, name},
        context.allocator,
    )
    if entry_err != nil {
        return "", false
    }
    prune_cache_entries(
        cache_dir,
        REPL_NATIVE_ARTIFACT_CACHE_LIMIT,
        ".kvist-repl-native-",
    )
    return entry, true
}

repl_native_artifact_cache_paths :: proc(
    entry: string,
) -> (artifact, metadata: string, ok: bool) {
    artifact_err: os.Error
    artifact, artifact_err = os.join_path(
        {entry, "generation.dylib"},
        context.allocator,
    )
    if artifact_err != nil {
        return "", "", false
    }
    metadata_err: os.Error
    metadata, metadata_err = os.join_path(
        {entry, "metadata.json"},
        context.allocator,
    )
    if metadata_err != nil {
        delete(artifact)
        return "", "", false
    }
    return artifact, metadata, true
}

repl_materialize_native_artifact :: proc(
    output_path,
    artifact_path: string,
) -> bool {
    // A hard link preserves the artifact's file identity. This matters on
    // platforms such as macOS where the dynamic loader caches validation and
    // fixup work by file identity: copying the same verified image to a fresh
    // generation path otherwise pays the full load cost in every REPL
    // process. Each session still gets its own path, and unlinking either the
    // cache entry or session directory cannot remove the other link.
    // Filesystems without hard-link support retain the previous copy path.
    if !os.exists(output_path) &&
       os.link(artifact_path, output_path) == nil {
        return true
    }
    return os.copy_file(output_path, artifact_path) == nil
}

repl_restore_native_artifact :: proc(
    entry,
    output_path: string,
) -> bool {
    artifact, metadata_path, paths_ok :=
        repl_native_artifact_cache_paths(entry)
    if !paths_ok {
        return false
    }
    defer delete(artifact)
    defer delete(metadata_path)
    if !os.exists(artifact) || !os.exists(metadata_path) {
        if os.exists(entry) {
            _ = os.remove_all(entry)
        }
        return false
    }
    metadata_bytes, metadata_err :=
        os.read_entire_file_from_path(metadata_path, context.allocator)
    if metadata_err != nil {
        _ = os.remove_all(entry)
        return false
    }
    defer delete(metadata_bytes)
    metadata := Repl_Native_Artifact_Metadata{}
    if json.unmarshal(metadata_bytes, &metadata) != nil ||
       metadata.version != REPL_NATIVE_ARTIFACT_CACHE_VERSION {
        _ = os.remove_all(entry)
        return false
    }
    size, _, size_ok := file_metadata(artifact)
    if !size_ok || size != metadata.size {
        _ = os.remove_all(entry)
        return false
    }
    content_hash, hash_ok := hash_file_content(artifact)
    if !hash_ok || content_hash != metadata.content_hash {
        _ = os.remove_all(entry)
        return false
    }
    if !repl_materialize_native_artifact(output_path, artifact) {
        return false
    }
    now := time.now()
    _ = os.change_times(entry, now, now)
    return true
}

repl_publish_native_artifact :: proc(
    entry,
    output_path: string,
) {
    if entry == "" || output_path == "" || os.exists(entry) {
        return
    }
    parent, _ := os.split_path(entry)
    temp_dir, temp_err := os.make_directory_temp(
        parent,
        ".kvist-repl-native-*",
        context.allocator,
    )
    if temp_err != nil {
        return
    }
    defer {
        _ = os.remove_all(temp_dir)
        delete(temp_dir)
    }
    artifact, metadata_path, paths_ok :=
        repl_native_artifact_cache_paths(temp_dir)
    if !paths_ok {
        return
    }
    defer delete(artifact)
    defer delete(metadata_path)
    if !repl_materialize_native_artifact(artifact, output_path) {
        return
    }
    size, _, size_ok := file_metadata(artifact)
    content_hash, hash_ok := hash_file_content(artifact)
    if !size_ok || !hash_ok {
        return
    }
    metadata := Repl_Native_Artifact_Metadata{
        version = REPL_NATIVE_ARTIFACT_CACHE_VERSION,
        content_hash = content_hash,
        size = size,
    }
    metadata_bytes, marshal_err := json.marshal(metadata)
    if marshal_err != nil {
        return
    }
    defer delete(metadata_bytes)
    if os.write_entire_file(metadata_path, metadata_bytes) != nil {
        return
    }
    _ = os.rename(temp_dir, entry)
}

repl_session_loaded_generation :: proc(
    session: ^Repl_Session,
    generation: int,
) -> (^Repl_Loaded_Generation, bool) {
    if session == nil {
        return nil, false
    }
    for &loaded in session.generations {
        if loaded.generation == generation {
            return &loaded, true
        }
    }
    return nil, false
}

repl_session_generation_is_loaded :: proc(
    session: ^Repl_Session,
    generation: int,
) -> bool {
    if session == nil {
        return false
    }
    for loaded in session.generations {
        if loaded.generation == generation {
            return true
        }
    }
    return false
}

repl_cached_generation :: proc(
    session: ^Repl_Session,
    source_hash: u64,
) -> (^Repl_Compiled_Generation, bool) {
    if session == nil {
        return nil, false
    }
    for i := len(session.compiled_generations)-1; i >= 0; i -= 1 {
        cached := &session.compiled_generations[i]
        if cached.source_hash == source_hash &&
           os.exists(cached.library_path) {
            if _, loaded := repl_session_loaded_generation(
                session,
                cached.generation,
            ); loaded {
                return cached, true
            }
        }
    }
    return nil, false
}

repl_cached_frontend_generation :: proc(
    session: ^Repl_Session,
    request_hash: u64,
    resident_request_hash: u64,
    recent_result_types: []string,
    allow_resident_direct := true,
    allow_native := true,
) -> (^Repl_Compiled_Generation, ^Repl_Loaded_Generation, bool) {
    if session == nil || request_hash == 0 {
        return nil, nil, false
    }
    for i := len(session.compiled_generations)-1; i >= 0; i -= 1 {
        cached := &session.compiled_generations[i]
        direct := repl_is_resident_direct_command(cached.library_path)
        expected_hash := resident_request_hash if direct else request_hash
        if cached.request_hash != expected_hash ||
           (direct && !allow_resident_direct) ||
           (!direct && !allow_native) ||
           (!direct && !os.exists(cached.library_path)) {
            continue
        }
        dependencies_valid := true
        for record in cached.dependency_files {
            if !file_fingerprint_matches_metadata(record) {
                dependencies_valid = false
                break
            }
        }
        if dependencies_valid {
            for record in cached.dependency_directories {
                if !directory_fingerprint_matches_metadata(record) {
                    dependencies_valid = false
                    break
                }
            }
        }
        if !dependencies_valid {
            continue
        }
        if direct {
            history_compatible := true
            for index := 0; index < 3; index += 1 {
                bit := u8(1) << u8(index)
                if cached.resident_recent_result_mask&bit == 0 {
                    continue
                }
                if index >= len(recent_result_types) ||
                   cached.resident_recent_result_types[index] !=
                       recent_result_types[index] {
                    history_compatible = false
                    break
                }
            }
            if !history_compatible {
                continue
            }
            return cached, nil, true
        }
        if loaded, found := repl_session_loaded_generation(
            session,
            cached.generation,
        ); found && os.exists(loaded.source_path) &&
           os.exists(loaded.map_path) {
            return cached, loaded, true
        }
    }
    return nil, nil, false
}

repl_record_compiled_generation :: proc(
    session: ^Repl_Session,
    source_hash,
    request_hash: u64,
    generation: int,
    library_path,
    emitted_source,
    warning_text: string,
    diagnostics: []Repl_Diagnostic,
    source_map: []kvist.Source_Map_Entry,
    generated_bytes: int,
) {
    if session == nil {
        return
    }
    cached := Repl_Compiled_Generation{
        source_hash = source_hash,
        request_hash = request_hash,
        generation = generation,
        library_path = strings.clone(library_path),
        emitted_source = strings.clone(emitted_source),
        warning_text = strings.clone(warning_text),
        generated_bytes = generated_bytes,
    }
    for diagnostic in diagnostics {
        append(&cached.diagnostics, repl_diagnostic_clone(diagnostic))
    }
    seen_files := make(map[string]bool, context.temp_allocator)
    seen_directories := make(map[string]bool, context.temp_allocator)
    for entry in source_map {
        path := entry.source_path
        if path == "" || seen_files[path] || !os.exists(path) {
            continue
        }
        seen_files[path] = true
        if size, modified, metadata_ok := file_metadata(path); metadata_ok {
            append(
                &cached.dependency_files,
                Dependency_File_Fingerprint{
                    path = strings.clone(path),
                    size = size,
                    modification_time_ns = modified,
                },
            )
        }
        directory, _ := os.split_path(path)
        if directory == "" || seen_directories[directory] {
            continue
        }
        seen_directories[directory] = true
        if modified, metadata_ok := directory_metadata(directory); metadata_ok {
            append(
                &cached.dependency_directories,
                Dependency_Directory_Fingerprint{
                    path = strings.clone(directory),
                    modification_time_ns = modified,
                },
            )
        }
    }
    append(&session.compiled_generations, cached)
}

repl_record_compiled_generation_alias :: proc(
    session: ^Repl_Session,
    source: ^Repl_Compiled_Generation,
    generation: int,
    library_path: string,
) {
    if session == nil || source == nil {
        return
    }
    cached := Repl_Compiled_Generation{
        source_hash = source.source_hash,
        request_hash = source.request_hash,
        generation = generation,
        library_path = strings.clone(library_path),
        emitted_source = strings.clone(source.emitted_source),
        warning_text = strings.clone(source.warning_text),
        resident_recent_result_mask = source.resident_recent_result_mask,
        generated_bytes = source.generated_bytes,
    }
    for diagnostic in source.diagnostics {
        append(&cached.diagnostics, repl_diagnostic_clone(diagnostic))
    }
    for record in source.dependency_files {
        append(&cached.dependency_files, Dependency_File_Fingerprint{
            path = strings.clone(record.path),
            size = record.size,
            modification_time_ns = record.modification_time_ns,
        })
    }
    for record in source.dependency_directories {
        append(
            &cached.dependency_directories,
            Dependency_Directory_Fingerprint{
                path = strings.clone(record.path),
                modification_time_ns = record.modification_time_ns,
            },
        )
    }
    for ty, index in source.resident_recent_result_types {
        cached.resident_recent_result_types[index] = strings.clone(ty)
    }
    append(&session.compiled_generations, cached)
}

repl_record_resident_frontend_generation :: proc(
    session: ^Repl_Session,
    request_hash: u64,
    generation: int,
    command,
    emitted_source: string,
    recent_result_mask: u8,
    recent_result_types: []string,
) {
    if session == nil || request_hash == 0 || command == "" {
        return
    }
    cached := Repl_Compiled_Generation{
        request_hash = request_hash,
        generation = generation,
        library_path = strings.clone(command),
        emitted_source = strings.clone(emitted_source),
        resident_recent_result_mask = recent_result_mask,
    }
    for index := 0; index < 3 && index < len(recent_result_types); index += 1 {
        if recent_result_mask&(u8(1) << u8(index)) != 0 {
            cached.resident_recent_result_types[index] =
                strings.clone(recent_result_types[index])
        }
    }
    if len(session.compiled_generations) > 0 {
        latest := &session.compiled_generations[
            len(session.compiled_generations)-1
        ]
        for record in latest.dependency_files {
            append(&cached.dependency_files, Dependency_File_Fingerprint{
                path = strings.clone(record.path),
                size = record.size,
                modification_time_ns = record.modification_time_ns,
            })
        }
        for record in latest.dependency_directories {
            append(
                &cached.dependency_directories,
                Dependency_Directory_Fingerprint{
                    path = strings.clone(record.path),
                    modification_time_ns = record.modification_time_ns,
                },
            )
        }
    }
    append(&session.compiled_generations, cached)
}

repl_retarget_nested_pause_generation :: proc(
    frames: ^[dynamic]Repl_Debug_Frame,
    from_generation,
    to_generation: int,
) {
    if frames == nil || from_generation == to_generation {
        return
    }
    from_prefix := fmt.tprintf("pause-%d-", from_generation)
    to_prefix := fmt.tprintf("pause-%d-", to_generation)
    for &frame in frames^ {
        if !strings.has_prefix(frame.pause_id, from_prefix) {
            continue
        }
        suffix := frame.pause_id[len(from_prefix):]
        new_pause_id := strings.clone(fmt.tprintf("%s%s", to_prefix, suffix))
        frame.pause_id = new_pause_id
        frame.frame_id = strings.clone(fmt.tprintf("frame-%s", new_pause_id))
    }
}

repl_compile_generation :: proc(
    input,
    source,
    session_source,
    session_dir: string,
    session: ^Repl_Session,
    generation: int,
    no_print: bool,
    recent_result_types: []string,
    eval_source_path := "",
    eval_start_line := 1,
    eval_start_column := 1,
    breakpoint_locations: ^[dynamic]Repl_Breakpoint_Location = nil,
    debug_frames: ^[dynamic]Repl_Debug_Frame = nil,
    pause_id := "",
    inspect_only := false,
    inspection_source_slot := "",
    inspection_source_type := "",
    inspection_result_slot := "",
    inspection_page_offset := 0,
    inspection_page_limit := 0,
    warning_text: ^string = nil,
    diagnostics: ^[dynamic]Repl_Diagnostic = nil,
    timings: ^Repl_Eval_Timings = nil,
    native_debug_symbols := false,
    capture_debug_values := false,
    fast_native_build := false,
    allow_execution_plan := true,
    allow_resident_scalar := true,
    require_resident_execution := false,
    allow_loaded_native_reuse := false,
) -> (library_path: string, emitted_source: string, diagnostic: string, ok: bool) {
    frontend_start := time.tick_now()
    if timings != nil {
        timings.execution_path = "native-compile"
    }
    resident_execution_eligible :=
       (allow_execution_plan || allow_resident_scalar) &&
       session != nil &&
       (len(session.generations) > 0 ||
        len(session.resident_scalar_invokes) > 0) &&
       pause_id == "" && !inspect_only && !no_print &&
       !native_debug_symbols && !capture_debug_values
    if resident_execution_eligible && len(session.generations) > 0 {
        resident_execution_eligible =
            repl_latest_generation_dependencies_valid(session)
    }
    stale_proc_names: [dynamic]string
    defer kvist.repl_string_slice_delete(stale_proc_names[:])
    if session != nil {
        for binding in session.bindings {
            if binding.stale &&
               (binding.kind == "defn" || binding.kind == "defn-") {
                append(&stale_proc_names, kvist.map_name(binding.name))
            }
        }
    }
    if resident_execution_eligible {
        direct, result_source, direct_ok := "", "", false
        if allow_resident_scalar {
            direct, result_source, direct_ok =
                repl_resident_scalar_invocation(source, session)
        }
        if direct_ok {
            if timings != nil {
                timings.frontend_ns = time.duration_nanoseconds(
                    time.tick_since(frontend_start),
                )
                timings.execution_path = "resident-scalar"
            }
            return direct, result_source, "", true
        }
    }
    loaded_native_reuse_eligible :=
        allow_loaded_native_reuse && session != nil &&
        len(session.generations) > 0 && pause_id == "" &&
        !inspect_only && !native_debug_symbols && !capture_debug_values
    dependency_key, _ := cached_compile_cache_key(input)
    defer delete(dependency_key)
    request_hash, resident_request_hash, frontend_cacheable :=
        repl_frontend_request_hash(
        dependency_key,
        source,
        session_source,
        no_print,
        recent_result_types,
        stale_proc_names[:],
        session.resident_scalar_invokes[:],
        eval_source_path,
        eval_start_line,
        eval_start_column,
        inspect_only,
        inspection_source_slot,
        inspection_source_type,
        inspection_result_slot,
        inspection_page_offset,
        inspection_page_limit,
        capture_debug_values,
        fast_native_build,
    )
    if frontend_cacheable && pause_id == "" && !native_debug_symbols {
        if cached, loaded, found := repl_cached_frontend_generation(
            session,
            request_hash,
            resident_request_hash,
            recent_result_types,
            resident_execution_eligible && allow_execution_plan,
            !require_resident_execution,
        ); found {
            if repl_is_resident_direct_command(cached.library_path) {
                if timings != nil {
                    timings.frontend_ns = time.duration_nanoseconds(
                        time.tick_since(frontend_start),
                    )
                    timings.frontend_cache_hit = true
                    timings.execution_path = "resident-cache"
                }
                return strings.clone(cached.library_path),
                       strings.clone(cached.emitted_source),
                       "",
                       true
            }
            if loaded_native_reuse_eligible &&
               repl_session_generation_is_loaded(
                   session,
                   cached.generation,
               ) {
                if warning_text != nil {
                    warning_text^ = strings.clone(cached.warning_text)
                }
                if diagnostics != nil {
                    for item in cached.diagnostics {
                        append(diagnostics, repl_diagnostic_clone(item))
                    }
                }
                if timings != nil {
                    timings.frontend_ns = time.duration_nanoseconds(
                        time.tick_since(frontend_start),
                    )
                    timings.generated_bytes = cached.generated_bytes
                    timings.native_cache_hit = true
                    timings.frontend_cache_hit = true
                    timings.execution_path = "native-loaded"
                }
                return repl_loaded_native_command(cached.library_path),
                       strings.clone(cached.emitted_source),
                       "",
                       true
            }
            source_generation_start := time.tick_now()
            source_path, output_path, paths_ok :=
                repl_generation_paths(session_dir, generation)
            map_path, map_ok :=
                repl_generation_map_path(session_dir, generation)
            copied := paths_ok && map_ok &&
                os.copy_file(source_path, loaded.source_path) == nil &&
                os.copy_file(map_path, loaded.map_path) == nil &&
                os.copy_file(output_path, cached.library_path) == nil
            if copied {
                if breakpoint_locations != nil {
                    for location in loaded.breakpoint_locations {
                        cloned := location
                        cloned.source_path = strings.clone(location.source_path)
                        cloned.generated_path = strings.clone(source_path)
                        append(breakpoint_locations, cloned)
                    }
                }
                if debug_frames != nil {
                    for frame in loaded.pause_points {
                        cloned := repl_debug_frame_clone(frame)
                        cloned.generation = generation
                        append(debug_frames, cloned)
                    }
                }
                if warning_text != nil {
                    warning_text^ = strings.clone(cached.warning_text)
                }
                if diagnostics != nil {
                    for item in cached.diagnostics {
                        append(diagnostics, repl_diagnostic_clone(item))
                    }
                }
                if timings != nil {
                    timings.frontend_ns =
                        time.duration_nanoseconds(
                            time.tick_since(frontend_start),
                        )
                    timings.source_generation_ns =
                        time.duration_nanoseconds(
                            time.tick_since(source_generation_start),
                        )
                    timings.generated_bytes = cached.generated_bytes
                    timings.native_cache_hit = true
                    timings.frontend_cache_hit = true
                    timings.execution_path = "native-cache"
                }
                repl_record_compiled_generation_alias(
                    session,
                    cached,
                    generation,
                    output_path,
                )
                delete(source_path)
                delete(map_path)
                return output_path,
                       strings.clone(cached.emitted_source),
                       "",
                       true
            }
            if paths_ok {
                _ = os.remove(source_path)
                _ = os.remove(output_path)
                delete(source_path)
                delete(output_path)
            }
            if map_ok {
                _ = os.remove(map_path)
                delete(map_path)
            }
        }
    }

    input_data := read_source_or_exit(input)
    defer delete(transmute([]byte)input_data)

    context_cache_key := repl_context_cache_key_with_dependency(
        dependency_key,
        session_source,
        source,
    )
    defer delete(context_cache_key)
    semantic_plan := kvist.Repl_Execution_Plan{}
    defer kvist.repl_execution_plan_delete(&semantic_plan)
    incremental_program := kvist.Repl_Incremental_Program{}
    defer kvist.repl_incremental_program_delete(&incremental_program)
    incremental_program_eligible :=
        allow_execution_plan && session != nil && pause_id == "" &&
        !inspect_only && !native_debug_symbols && !capture_debug_values &&
        kvist_repl.incremental_native_backend_supported()
    result, compile_err, compiled := kvist.compile_eval_path_with_map(
        input,
        source,
        no_print,
        &timings.profile if timings != nil else nil,
        repl_generation = true,
        repl_session_source = session_source,
        repl_recent_result_types = recent_result_types,
        repl_inspect_only = inspect_only,
        repl_inspection_source_slot = inspection_source_slot,
        repl_inspection_source_type = inspection_source_type,
        repl_inspection_result_slot = inspection_result_slot,
        repl_inspection_page_offset = inspection_page_offset,
        repl_inspection_page_limit = inspection_page_limit,
        repl_debug_capture_values = capture_debug_values,
        repl_context_cache_key = context_cache_key,
        repl_execution_plan = &semantic_plan if
            resident_execution_eligible && allow_execution_plan else nil,
        repl_stale_proc_names = stale_proc_names[:],
        repl_scalar_invokes = session.resident_scalar_invokes[:],
        repl_incremental_program = &incremental_program if
            incremental_program_eligible else nil,
    )
    if timings != nil {
        timings.frontend_ns =
            time.duration_nanoseconds(time.tick_since(frontend_start))
    }
    if !compiled {
        if diagnostics != nil {
            diagnostic_source := source
            diagnostic_path := eval_source_path
            diagnostic_start_line := eval_start_line
            diagnostic_start_column := eval_start_column
            if compile_err.span.source == .File {
                diagnostic_source = input_data
                diagnostic_path = input
                if compile_err.source_path != "" {
                    diagnostic_path = compile_err.source_path
                }
                diagnostic_start_line = 1
                diagnostic_start_column = 1
            }
            line, column, end_line, end_column :=
                repl_diagnostic_range(
                    diagnostic_source,
                    compile_err.span,
                    diagnostic_start_line,
                    diagnostic_start_column,
                )
            append(diagnostics, Repl_Diagnostic{
                severity = strings.clone("error"),
                phase = strings.clone("compile"),
                message = strings.clone(compile_err.message),
                source_path = strings.clone(diagnostic_path),
                line = line,
                column = column,
                end_line = end_line,
                end_column = end_column,
            })
        }
        formatted := kvist.format_eval_compile_error(input, input_data, source, compile_err)
        return "", "", formatted, false
    }
    if semantic_plan.encoded != "" {
        direct, result_source, direct_ok :=
            repl_execution_plan_command(semantic_plan)
        if direct_ok {
            if timings != nil {
                timings.execution_path = "resident-semantic-plan"
            }
            if frontend_cacheable && pause_id == "" &&
               !native_debug_symbols {
                repl_record_resident_frontend_generation(
                    session,
                    resident_request_hash,
                    generation,
                    direct,
                    result_source,
                    semantic_plan.recent_result_mask,
                    recent_result_types,
                )
            }
            return direct, result_source, "", true
        }
    }
    if require_resident_execution {
        if timings != nil {
            timings.execution_path = "resident-unsupported"
        }
        defer delete(result.output)
        defer kvist.source_map_slice_delete(result.source_map)
        defer kvist.compile_warning_slice_delete(result.warnings)
        message := strings.clone(
            "expression is not supported by resident execution; " +
            "use --execution auto or --execution native",
        )
        if diagnostics != nil {
            _, _, end_line, end_column :=
                repl_diagnostic_range(
                    source,
                    kvist.Span{
                        start = 0,
                        end = len(source),
                        source = .Eval,
                    },
                    eval_start_line,
                    eval_start_column,
                )
            append(diagnostics, Repl_Diagnostic{
                severity = strings.clone("error"),
                phase = strings.clone("resident-execution"),
                message = strings.clone(message),
                source_path = strings.clone(
                    eval_source_path if eval_source_path != "" else input,
                ),
                line = max(eval_start_line, 1),
                column = max(eval_start_column, 1),
                end_line = end_line,
                end_column = end_column,
            })
        }
        return "", "", message, false
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    dependency_source_map: [dynamic]kvist.Source_Map_Entry
    for entry in result.source_map {
        append(
            &dependency_source_map,
            kvist.clone_source_map_entry(entry),
        )
    }
    defer kvist.source_map_slice_delete(dependency_source_map)
    if warning_text != nil {
        warning_text^ =
            format_compile_warnings(
                input,
                input_data,
                source,
                result.warnings[:],
            )
    }
    if diagnostics != nil {
        for warning in result.warnings {
            warning_source := source
            owned_warning_source: []u8
            warning_path := eval_source_path
            warning_start_line := eval_start_line
            warning_start_column := eval_start_column
            if warning.span.source == .File {
                warning_source = input_data
                warning_path = input
                if warning.source_path != "" {
                    warning_path = warning.source_path
                    imported_source, read_err :=
                        os.read_entire_file_from_path(
                            warning.source_path,
                            context.allocator,
                        )
                    if read_err == nil {
                        owned_warning_source = imported_source
                        warning_source = string(imported_source)
                    }
                }
                warning_start_line = 1
                warning_start_column = 1
            }
            line, column, end_line, end_column :=
                repl_diagnostic_range(
                    warning_source,
                    warning.span,
                    warning_start_line,
                    warning_start_column,
            )
            code := kvist.compile_warning_code_text(warning.code)
            confidence := "definite"
            if warning.confidence == .Conservative {
                confidence = "conservative"
            }
            append(diagnostics, Repl_Diagnostic{
                severity = strings.clone("warning"),
                code = strings.clone(code),
                confidence = strings.clone(confidence),
                phase = strings.clone("compile"),
                message = strings.clone(warning.message),
                source_path = strings.clone(warning_path),
                line = line,
                column = column,
                end_line = end_line,
                end_column = end_column,
            })
            if owned_warning_source != nil {
                delete(owned_warning_source)
            }
        }
    }

    if incremental_program.encoded != "" {
        direct, direct_ok := repl_incremental_program_command(
            incremental_program,
        )
        if direct_ok {
            if timings != nil {
                timings.execution_path = "incremental-native"
            }
            return direct, strings.clone(result.output), "", true
        }
    }

    source_generation_start := time.tick_now()
    source_path, output_path, paths_ok := repl_generation_paths(session_dir, generation)
    if !paths_ok {
        return "", "", strings.clone("failed to allocate REPL generation paths"), false
    }
    defer delete(source_path)

    generation_source := result.output
    debug_source_path :=
        eval_source_path if eval_source_path != "" else input
    nested_source, nested_frames, nested_ok :=
        repl_instrument_nested_pause_points(
            result.output,
            input_data,
            input,
            source,
            debug_source_path,
            eval_start_line,
            eval_start_column,
            generation,
        )
    if !nested_ok {
        delete(output_path)
        return "", "", strings.clone("failed to instrument nested REPL pause points"), false
    }
    defer delete(nested_source)
    generation_source = nested_source
    thin_source := ""
    result_abi := kvist.repl_registered_result_abi(result.output)
    defer delete(result_abi)
    if session != nil && len(session.generations) > 0 &&
       !inspect_only && pause_id == "" && !native_debug_symbols &&
       !capture_debug_values {
        thin_source = repl_thin_generation_source(
            generation_source,
            &result.source_map,
            &nested_frames,
        )
        generation_source = thin_source
    }
    defer delete(thin_source)
    source_hash := repl_generation_source_hash(generation_source, generation)
    cached_generation: ^Repl_Compiled_Generation
    cache_hit := false
    if pause_id == "" && !native_debug_symbols {
        cached_generation, cache_hit =
            repl_cached_generation(
                session,
                source_hash,
            )
    }
    if debug_frames != nil {
        debug_frames^ = nested_frames
        if cache_hit {
            repl_retarget_nested_pause_generation(
                debug_frames,
                generation,
                cached_generation.generation,
            )
        }
    } else {
        repl_debug_frames_delete(&nested_frames)
    }
    if cache_hit && loaded_native_reuse_eligible &&
       repl_session_generation_is_loaded(
           session,
           cached_generation.generation,
       ) {
        delete(output_path)
        if timings != nil {
            timings.generated_bytes = cached_generation.generated_bytes
            timings.native_cache_hit = true
            timings.execution_path = "native-loaded"
        }
        return repl_loaded_native_command(cached_generation.library_path),
               strings.clone(result.output),
               "",
               true
    }
    injected_source := ""
    if pause_id != "" {
        injected_ok: bool
        injected_source, injected_ok =
            repl_inject_pause_before_entry(
                generation_source,
                pause_id,
                &result.source_map,
            )
        if !injected_ok {
            delete(output_path)
            return "", "", strings.clone("failed to instrument REPL pause point"), false
        }
        generation_source = injected_source
    }
    defer delete(injected_source)
    rebased, rebase_err, rebased_ok := kvist.rebase_emitted_odin_imports_for_output_path(
        generation_source,
        source_path,
    )
    if !rebased_ok {
        delete(output_path)
        return "", "", strings.clone(rebase_err.message), false
    }
    defer delete(rebased)
    if timings != nil {
        timings.generated_bytes = len(rebased)
    }
    if os.write_entire_file_from_string(source_path, rebased) != nil {
        delete(output_path)
        return "", "", strings.clone("failed to write REPL generation source"), false
    }
    map_path, map_path_ok :=
        repl_generation_map_path(session_dir, generation)
    if !map_path_ok {
        delete(output_path)
        return "", "", strings.clone("failed to allocate REPL generation map path"), false
    }
    defer delete(map_path)
    formatted_map := kvist.format_source_map(result.source_map[:])
    defer delete(formatted_map)
    if os.write_entire_file_from_string(map_path, formatted_map) != nil {
        delete(output_path)
        return "", "", strings.clone("failed to write REPL generation source map"), false
    }
    if breakpoint_locations != nil {
        breakpoint_locations^ =
            repl_generation_breakpoint_locations(
                result.source_map[:],
                input,
                input_data,
                source,
                eval_source_path,
                source_path,
                eval_start_line,
                eval_start_column,
                generation,
            )
    }

    if cache_hit {
        // Loading the same dynamic-library path twice can make the platform
        // loader return the existing image. The worker deliberately retains
        // every generation handle, so treating that image as a new generation
        // would duplicate one handle and corrupt teardown. Give the cached
        // machine code a generation-specific path instead. This still avoids
        // Odin compilation while preserving the worker's append-only model.
        copy_err := os.copy_file(output_path, cached_generation.library_path)
        if copy_err != nil {
            delete(output_path)
            return "", "", strings.clone("failed to copy cached REPL generation"), false
        }
        if timings != nil {
            timings.source_generation_ns =
                time.duration_nanoseconds(
                    time.tick_since(source_generation_start),
                )
            timings.native_cache_hit = true
            timings.execution_path = "native-cache"
        }
        cached_warning := ""
        if warning_text != nil {
            cached_warning = warning_text^
        }
        cached_diagnostics: []Repl_Diagnostic
        if diagnostics != nil {
            cached_diagnostics = diagnostics^[:]
        }
        repl_record_compiled_generation(
            session,
            source_hash,
            request_hash,
            generation,
            output_path,
            result.output,
            cached_warning,
            cached_diagnostics,
            dependency_source_map[:],
            len(rebased),
        )
        return output_path,
               strings.clone(result.output),
               "",
               true
    }

    native_artifact_entry := ""
    native_artifact_eligible :=
        session != nil && pause_id == "" && !inspect_only &&
        !native_debug_symbols && !capture_debug_values
    if native_artifact_eligible {
        artifact_entry, artifact_ok := repl_native_artifact_cache_entry(
            request_hash,
            source_hash,
            fast_native_build,
        )
        if artifact_ok {
            native_artifact_entry = artifact_entry
        }
    }
    defer delete(native_artifact_entry)
    if native_artifact_entry != "" &&
       repl_restore_native_artifact(
           native_artifact_entry,
           output_path,
       ) {
        if timings != nil {
            timings.source_generation_ns =
                time.duration_nanoseconds(
                    time.tick_since(source_generation_start),
                )
            timings.native_cache_hit = true
            timings.execution_path = "native-artifact-cache"
        }
        cached_warning := ""
        if warning_text != nil {
            cached_warning = warning_text^
        }
        cached_diagnostics: []Repl_Diagnostic
        if diagnostics != nil {
            cached_diagnostics = diagnostics^[:]
        }
        repl_record_compiled_generation(
            session,
            source_hash,
            request_hash,
            generation,
            output_path,
            result.output,
            cached_warning,
            cached_diagnostics,
            dependency_source_map[:],
            len(rebased),
        )
        return output_path,
               strings.clone(result.output),
               "",
               true
    }

    output_arg := strings.clone(fmt.tprintf("-out:%s", output_path))
    defer delete(output_arg)
    args := [5]string{
        "odin",
        "build",
        source_path,
        "-file",
        "-build-mode:dll",
    }
    command := make([dynamic]string, 0, 8)
    defer delete(command)
    append(&command, ..args[:])
    if fast_native_build {
        append(&command, "-o:none")
    }
    if native_debug_symbols {
        append(&command, "-debug")
    }
    append(&command, output_arg)
    if timings != nil {
        timings.source_generation_ns =
            time.duration_nanoseconds(time.tick_since(source_generation_start))
    }
    odin_build_start := time.tick_now()
    state, stdout, stderr, process_err := os.process_exec(
        os.Process_Desc{command = command[:]},
        context.allocator,
    )
    fast_build_compiler_failure := fast_native_build &&
        (process_err != nil || !state.exited || state.exit_code != 0) &&
        (strings.contains(string(stderr), "This is a compiler error") ||
         strings.contains(string(stderr), "Assertion Failure"))
    if fast_build_compiler_failure {
        // Odin's no-optimization path occasionally exposes compiler-only
        // assertions for otherwise valid programs. Preserve the fast editor
        // bulk path, but retry those compiler failures with the stable
        // optimized path before reporting an evaluation
        // error to the client.
        delete(stdout)
        delete(stderr)
        command[5] = "-o:speed"
        state, stdout, stderr, process_err = os.process_exec(
            os.Process_Desc{command = command[:]},
            context.allocator,
        )
    }
    if timings != nil {
        timings.odin_build_ns =
            time.duration_nanoseconds(time.tick_since(odin_build_start))
    }
    defer delete(stdout)
    defer delete(stderr)
    if process_err != nil || !state.exited || state.exit_code != 0 {
        combined := strings.builder_make()
        defer strings.builder_destroy(&combined)
        if len(stdout) > 0 {
            strings.write_string(&combined, string(stdout))
        }
        if len(stderr) > 0 {
            mapped := remap_odin_output_locations(
                string(stderr),
                source_path,
                input,
                input_data,
                source,
                result.source_map[:],
            )
            strings.write_string(&combined, mapped)
            delete(mapped)
        }
        if strings.to_string(combined) == "" {
            strings.write_string(&combined, "failed to build REPL generation")
        }
        if diagnostics != nil {
            _, _, end_line, end_column :=
                repl_diagnostic_range(
                    source,
                    kvist.Span{start = 0, end = len(source), source = .Eval},
                    eval_start_line,
                    eval_start_column,
                )
            odin_diagnostic_path := eval_source_path
            if odin_diagnostic_path == "" {
                odin_diagnostic_path = input
            }
            append(diagnostics, Repl_Diagnostic{
                severity = strings.clone("error"),
                phase = strings.clone("odin"),
                message = strings.clone(strings.to_string(combined)),
                source_path = strings.clone(odin_diagnostic_path),
                line = max(eval_start_line, 1),
                column = max(eval_start_column, 1),
                end_line = end_line,
                end_column = end_column,
            })
        }
        delete(output_path)
        return "", "", strings.clone(strings.to_string(combined)), false
    }
    if native_artifact_entry != "" {
        repl_publish_native_artifact(
            native_artifact_entry,
            output_path,
        )
    }
    if session != nil && pause_id == "" && !native_debug_symbols {
        cached_warning := ""
        if warning_text != nil {
            cached_warning = warning_text^
        }
        cached_diagnostics: []Repl_Diagnostic
        if diagnostics != nil {
            cached_diagnostics = diagnostics^[:]
        }
        repl_record_compiled_generation(
            session,
            source_hash,
            request_hash,
            generation,
            output_path,
            result.output,
            cached_warning,
            cached_diagnostics,
            dependency_source_map[:],
            len(rebased),
        )
    }
    return output_path, strings.clone(result.output), "", true
}

repl_handle_eval :: proc(
    input,
    source,
    session_dir: string,
    generation: int,
    no_print: bool,
    worker: ^Repl_Worker_Process,
    session: ^Repl_Session,
    eval_source_path := "",
    eval_start_line := 1,
    eval_start_column := 1,
    pause_id := "",
    protocol_reader: ^bufio.Reader = nil,
    parent_request: ^Repl_Request = nil,
    inspect_only := false,
    inspection_abi: ^string = nil,
    inspection_source_slot := "",
    inspection_source_type := "",
    inspection_result_slot := "",
    inspection_page_offset := 0,
    inspection_page_limit := 0,
    trace := false,
    trace_limit := REPL_DEFAULT_TRACE_LIMIT,
    trace_values := false,
    trace_value_limit := REPL_DEFAULT_TRACE_VALUE_LIMIT,
    generation_counter: ^int = nil,
    nested_worker_execution := false,
    nesting_depth := 0,
    preserve_definition_locations := false,
    compile_warning_text: ^string = nil,
    diagnostics: ^[dynamic]Repl_Diagnostic = nil,
    timeout_ms := 0,
    timings: ^Repl_Eval_Timings = nil,
    native_debug_symbols := false,
    defer_debug_values := false,
    execution_mode := Repl_Execution_Mode.Auto,
) -> (output, message: string, ok: bool) {
    total_start := time.tick_now()
    defer if timings != nil {
        timings.total_ns =
            time.duration_nanoseconds(time.tick_since(total_start))
    }
    compiled_source, normalize_err, normalized :=
        kvist.repl_normalize_source_path(
            input,
            source,
            eval_source_path if eval_source_path != "" else input,
        )
    if !normalized {
        return "", strings.clone(normalize_err.message), false
    }
    defer delete(compiled_source)
    preparation_start := time.tick_now()
    retained_source := repl_session_source(session)
    defer delete(retained_source)
    recent_result_types := repl_session_recent_result_types(session)
    defer delete(recent_result_types)
    breakpoint_locations: [dynamic]Repl_Breakpoint_Location
    defer repl_breakpoint_locations_delete(&breakpoint_locations)
    debug_frames: [dynamic]Repl_Debug_Frame
    defer repl_debug_frames_delete(&debug_frames)
    if timings != nil {
        timings.preparation_ns =
            time.duration_nanoseconds(time.tick_since(preparation_start))
    }
    persistent_definitions :=
        kvist.repl_persistent_definitions_source(compiled_source)
    defer delete(persistent_definitions)
    persistent_imports :=
        kvist.repl_persistent_imports_source(compiled_source)
    defer delete(persistent_imports)
    replace_resident_scalar_invokes :=
        session == nil || len(session.generations) == 0 ||
        persistent_definitions != "" || persistent_imports != "" ||
        !repl_latest_generation_dependencies_valid(session)
    resident_plan_enabled :=
        repl_execution_mode_allows_plan(execution_mode)
    resident_adapter_enabled :=
        repl_execution_mode_allows_adapter(execution_mode)
    require_resident_execution :=
        execution_mode == .Resident &&
        persistent_definitions == "" && persistent_imports == ""
    capture_debug_values :=
        trace || pause_id != "" || native_debug_symbols ||
        nested_worker_execution ||
        (!defer_debug_values && len(persistent_definitions) > 0)
    library_path, emitted_source, diagnostic, compiled := repl_compile_generation(
        input,
        compiled_source,
        retained_source,
        session_dir,
        session,
        generation,
        no_print,
        recent_result_types[:],
        eval_source_path,
        eval_start_line,
        eval_start_column,
        &breakpoint_locations,
        &debug_frames,
        pause_id,
        inspect_only,
        inspection_source_slot,
        inspection_source_type,
        inspection_result_slot,
        inspection_page_offset,
        inspection_page_limit,
        compile_warning_text,
        diagnostics,
        timings,
        native_debug_symbols,
        capture_debug_values,
        defer_debug_values,
        allow_execution_plan = resident_plan_enabled,
        allow_resident_scalar = resident_adapter_enabled,
        require_resident_execution = require_resident_execution,
        allow_loaded_native_reuse =
            persistent_definitions == "" && persistent_imports == "" &&
            repl_execution_mode_allows_loaded_native(execution_mode),
    )
    if !compiled {
        return "", diagnostic, false
    }
    defer delete(library_path)
    defer delete(emitted_source)
    direct_invocation := repl_is_direct_worker_command(library_path)
    incremental_invocation := strings.has_prefix(
        library_path,
        kvist_repl.WORKER_INCREMENTAL_PROGRAM_PREFIX,
    )
    ran: bool
    worker_run_start := time.tick_now()
    output, message, ran =
        repl_worker_run_generation(
            worker,
            library_path,
            protocol_reader,
            parent_request,
            session,
            generation,
            trace,
            trace_limit,
            trace_values,
            trace_value_limit,
            debug_frames[:],
            input,
            session_dir,
            generation_counter,
            nested_worker_execution,
            nesting_depth,
            timeout_ms,
            timings,
        )
    if timings != nil {
        timings.worker_run_ns =
            time.duration_nanoseconds(time.tick_since(worker_run_start))
    }
    if !ran && incremental_invocation && worker.alive {
        // The incremental backend is optional and deliberately not a second
        // semantic authority. If it rejects a compiler-approved program after
        // the controller probe, execute the already-valid submission through
        // the ordinary native pipeline. The worker installs an incremental
        // batch only after every procedure and adapter has resolved, so no
        // definitions have been published at this point.
        incremental_frontend_ns: i64
        incremental_worker_ns: i64
        if timings != nil {
            incremental_frontend_ns = timings.frontend_ns
            incremental_worker_ns = timings.worker_run_ns
        }
        delete(output)
        delete(message)
        delete(library_path)
        delete(emitted_source)
        delete(diagnostic)
        library_path, emitted_source, diagnostic, compiled =
            repl_compile_generation(
                input,
                compiled_source,
                retained_source,
                session_dir,
                session,
                generation,
                no_print,
                recent_result_types[:],
                eval_source_path,
                eval_start_line,
                eval_start_column,
                &breakpoint_locations,
                &debug_frames,
                pause_id,
                inspect_only,
                inspection_source_slot,
                inspection_source_type,
                inspection_result_slot,
                inspection_page_offset,
                inspection_page_limit,
                nil,
                nil,
                timings,
                native_debug_symbols,
                capture_debug_values,
                defer_debug_values,
                allow_execution_plan = false,
                allow_resident_scalar = false,
                require_resident_execution = false,
                allow_loaded_native_reuse = false,
            )
        if timings != nil {
            timings.frontend_ns += incremental_frontend_ns
            timings.execution_path = "native-fallback"
        }
        if !compiled {
            return "", diagnostic, false
        }
        direct_invocation = repl_is_direct_worker_command(library_path)
        incremental_invocation = false
        worker_run_start = time.tick_now()
        output, message, ran =
            repl_worker_run_generation(
                worker,
                library_path,
                protocol_reader,
                parent_request,
                session,
                generation,
                trace,
                trace_limit,
                trace_values,
                trace_value_limit,
                debug_frames[:],
                input,
                session_dir,
                generation_counter,
                nested_worker_execution,
                nesting_depth,
                timeout_ms,
                timings,
            )
        if timings != nil {
            timings.worker_run_ns = incremental_worker_ns +
                time.duration_nanoseconds(time.tick_since(worker_run_start))
        }
    }
    if ran {
        commit_start := time.tick_now()
        if incremental_invocation {
            _ = repl_session_record_incremental_scalar_invokes(
                session,
                library_path,
                replace_resident_scalar_invokes,
            )
        } else if !direct_invocation {
            generation_source_path, generation_library_path, generation_paths_ok :=
                repl_generation_paths(session_dir, generation)
            generation_map_path, generation_map_ok :=
                repl_generation_map_path(session_dir, generation)
            if generation_paths_ok {
                repl_session_record_generation_scalar_invokes(
                    session,
                    generation_source_path,
                    replace_resident_scalar_invokes,
                )
            } else if replace_resident_scalar_invokes {
                repl_session_replace_scalar_invokes(session)
            }
            if generation_paths_ok && generation_map_ok {
                repl_session_commit_generation(
                    session,
                    generation,
                    generation_source_path,
                    generation_map_path,
                    library_path,
                    breakpoint_locations[:],
                    debug_frames[:],
                    native_debug_symbols,
                )
            }
            if generation_paths_ok {
                delete(generation_source_path)
                delete(generation_library_path)
            }
            if generation_map_ok {
                delete(generation_map_path)
            }
        }
        result_abi := kvist.repl_registered_result_abi(emitted_source)
        if inspect_only {
            delete(result_abi)
            result_abi = kvist.repl_inspection_result_abi(emitted_source)
            if inspection_abi != nil {
                inspection_abi^ = strings.clone(result_abi)
            }
        }
        if result_abi != "" {
            result_ty := kvist.repl_result_type_from_abi(result_abi)
            if result_ty != "" && !inspect_only {
                repl_session_rotate_result(
                    session,
                    result_ty,
                    result_abi,
                    generation,
                )
            }
            delete(result_ty)
        }
        delete(result_abi)
        if !inspect_only {
            definitions := kvist.repl_persistent_definitions_source(compiled_source)
            if definitions != "" {
                repl_session_commit(
                    session,
                    definitions,
                    source,
                    emitted_source,
                    generation,
                    eval_source_path if eval_source_path != "" else input,
                    eval_start_line,
                    eval_start_column,
                    preserve_definition_locations,
                    defer_debug_values || incremental_invocation,
                )
            }
            delete(definitions)
        }
        if timings != nil {
            timings.commit_ns =
                time.duration_nanoseconds(time.tick_since(commit_start))
        }
    }
    if !worker.alive {
        // A crashed native worker loses its loaded code and slot registry.
        // Keep no phantom compiler bindings in the replacement worker.
        repl_session_clear(session)
    }
    return output, message, ran
}

repl_protocol_loop :: proc(
    input,
    session_dir: string,
    worker: ^Repl_Worker_Process,
    session: ^Repl_Session,
    execution_mode := Repl_Execution_Mode.Auto,
) -> int {
    reader := bufio.Reader{}
    bufio.reader_init(&reader, os.to_reader(os.stdin))
    defer bufio.reader_destroy(&reader)
    generation := 0
    worker_epoch := 1

    ready_event :=
        repl_debug_event("", "ready", worker, worker_epoch, generation)
    ready_event.execution_mode = repl_execution_mode_name(execution_mode)
    repl_emit_json_event(ready_event)

    for {
        raw, ok := repl_read_line(&reader)
        if !ok {
            return 0
        }
        line := repl_trim_line(raw)
        request := Repl_Request{}
        unmarshal_err := json.unmarshal(transmute([]byte)line, &request)
        delete(raw)
        if unmarshal_err != nil {
            repl_delete_request(&request)
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                kind = "protocol-error",
                success = false,
                message = "invalid JSONL request",
            })
            continue
        }

        if request.op == "close" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = true,
            })
            repl_delete_request(&request)
            return 0
        }
        if request.op == "interrupt" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                generation = generation,
                message =
                    "no active standalone evaluation; interrupt is accepted while a request is paused",
            })
            repl_delete_request(&request)
            continue
        }
        if request.op == "reset" {
            repl_stop_worker(worker)
            next_worker, start_message, started := repl_start_worker()
            if started {
                worker^ = next_worker
                generation = 0
                worker_epoch += 1
                repl_session_clear(session)
            }
            reset_event :=
                repl_debug_event(
                    request.id,
                    "reset",
                    worker,
                    worker_epoch,
                    generation,
                )
            reset_event.success = started
            reset_event.message = start_message
            repl_emit_json_event(reset_event)
            if start_message != "" {
                delete(start_message)
            }
            repl_delete_request(&request)
            continue
        }
        if repl_is_tooling_op(request.op) {
            repl_emit_tooling_request(
                input,
                session,
                &request,
                generation,
            )
            repl_delete_request(&request)
            continue
        }
        if request.op == "checkpoint" ||
           request.op == "checkpoint-restore" ||
           request.op == "checkpoint-drop" {
            command := "__checkpoint__"
            kind := "checkpoint-saved"
            if request.op == "checkpoint-restore" {
                command = "__checkpoint_restore__"
                kind = "checkpoint-restored"
            } else if request.op == "checkpoint-drop" {
                command = "__checkpoint_drop__"
                kind = "checkpoint-dropped"
            }
            count := 0
            operation_message := ""
            operation_ok := false
            if request.name == "" {
                operation_message =
                    strings.clone("checkpoint name must not be empty")
            } else if ensure_message, ensured :=
                repl_ensure_worker(worker);
                !ensured {
                operation_message = ensure_message
            } else {
                count, operation_message, operation_ok =
                    repl_worker_checkpoint_command(
                        worker,
                        command,
                        request.name,
                    )
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = kind,
                success = operation_ok,
                generation = generation,
                message = operation_message,
                checkpoint = request.name,
                checkpoint_bindings = count,
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = operation_ok,
                generation = generation,
                message = operation_message,
            })
            if operation_message != "" {
                delete(operation_message)
            }
            repl_delete_request(&request)
            continue
        }
        if request.op == "checkpoints" {
            checkpoints: [dynamic]Repl_Checkpoint
            inventory_message := ""
            inventory_ok := false
            if ensure_message, ensured := repl_ensure_worker(worker);
               !ensured {
                inventory_message = ensure_message
            } else {
                checkpoints, inventory_message, inventory_ok =
                    repl_worker_checkpoints(worker)
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "checkpoints",
                success = inventory_ok,
                generation = generation,
                message = inventory_message,
                checkpoints = checkpoints[:],
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = inventory_ok,
                generation = generation,
                message = inventory_message,
            })
            repl_checkpoint_slice_delete(&checkpoints)
            if inventory_message != "" {
                delete(inventory_message)
            }
            repl_delete_request(&request)
            continue
        }
        if request.op == "runtime-allocations" {
            stats := kvist_repl.Worker_Allocation_Stats{}
            stats_message := ""
            stats_ok := false
            if ensure_message, ensured := repl_ensure_worker(worker);
               !ensured {
                stats_message = ensure_message
            } else {
                stats, stats_message, stats_ok =
                    repl_worker_allocation_stats(worker)
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "runtime-allocations",
                success = stats_ok,
                generation = generation,
                message = stats_message,
                runtime_live_allocations =
                    Repl_Optional_Int(stats.live_allocations),
                runtime_live_bytes =
                    Repl_Optional_Int(stats.live_bytes),
                runtime_total_allocations =
                    Repl_Optional_Int(stats.total_allocations),
                runtime_total_allocated_bytes =
                    Repl_Optional_Int(
                        stats.total_allocated_bytes,
                    ),
                runtime_total_frees =
                    Repl_Optional_Int(stats.total_frees),
                runtime_total_freed_bytes =
                    Repl_Optional_Int(stats.total_freed_bytes),
                managed_live_allocations =
                    Repl_Optional_Int(stats.managed_live_allocations),
                managed_live_bytes =
                    Repl_Optional_Int(stats.managed_live_bytes),
                managed_peak_bytes =
                    Repl_Optional_Int(stats.managed_peak_bytes),
                managed_total_allocations =
                    Repl_Optional_Int(
                        stats.managed_total_allocations,
                    ),
                managed_total_allocated_bytes =
                    Repl_Optional_Int(
                        stats.managed_total_allocated_bytes,
                    ),
                managed_total_frees =
                    Repl_Optional_Int(stats.managed_total_frees),
                managed_total_freed_bytes =
                    Repl_Optional_Int(
                        stats.managed_total_freed_bytes,
                    ),
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = stats_ok,
                generation = generation,
                message = stats_message,
            })
            if stats_message != "" {
                delete(stats_message)
            }
            repl_delete_request(&request)
            continue
        }
        if request.op == "physical-allocations" {
            allocations: [dynamic]Repl_Physical_Allocation
            transfers: [dynamic]Repl_Physical_Transfer
            inventory_message := ""
            inventory_ok := false
            if ensure_message, ensured := repl_ensure_worker(worker);
               !ensured {
                inventory_message = ensure_message
            } else {
                allocations, transfers,
                    inventory_message, inventory_ok =
                    repl_worker_physical_allocations(worker)
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "physical-allocations",
                success = inventory_ok,
                generation = generation,
                message = inventory_message,
                physical_allocations = allocations[:],
                physical_allocation_count =
                    Repl_Optional_Int(len(allocations)),
                physical_transfers = transfers[:],
                physical_transfer_count =
                    Repl_Optional_Int(len(transfers)),
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = inventory_ok,
                generation = generation,
                message = inventory_message,
            })
            repl_physical_allocation_slice_delete(&allocations)
            repl_physical_transfer_slice_delete(&transfers)
            if inventory_message != "" {
                delete(inventory_message)
            }
            repl_delete_request(&request)
            continue
        }
        if request.op == "bindings" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "bindings",
                success = true,
                generation = generation,
                bindings = session.bindings[:],
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&request)
            continue
        }
        if request.op == "results" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "results",
                success = true,
                generation = generation,
                results = session.results[:session.result_count],
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&request)
            continue
        }
        if request.op == "allocations" {
            allocations, known_bytes, known_count :=
                repl_session_allocations(session)
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "allocations",
                success = true,
                generation = generation,
                allocations = allocations[:],
                allocation_count =
                    Repl_Optional_Int(len(allocations)),
                known_allocation_bytes =
                    Repl_Optional_Int(known_bytes),
                known_allocation_count =
                    Repl_Optional_Int(known_count),
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            delete(allocations)
            repl_delete_request(&request)
            continue
        }
        if request.op == "ownership-history" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "ownership-history",
                success = true,
                generation = generation,
                ownership_events = session.ownership_events[:],
                ownership_event_count =
                    Repl_Optional_Int(
                        len(session.ownership_events),
                    ),
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&request)
            continue
        }
        if request.op == "generations" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "generations",
                success = true,
                generation = generation,
                generations = session.generations[:],
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&request)
            continue
        }
        if request.op == "debug-session" {
            repl_emit_json_event(
                repl_debug_event(
                    request.id,
                    "debug-session",
                    worker,
                    worker_epoch,
                    generation,
                ),
            )
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = worker.alive,
                generation = generation,
            })
            repl_delete_request(&request)
            continue
        }
        if request.op == "breakpoint-locations" {
            requested_line, has_requested_line := request.line.(int)
            requested_column, has_requested_column := request.column.(int)
            if request.source_path == "" ||
               !has_requested_line ||
               requested_line <= 0 ||
               (has_requested_column && requested_column <= 0) {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message =
                        "breakpoint-locations requires source_path and a positive line/column",
                })
                repl_delete_request(&request)
                continue
            }
            matches: [dynamic]Repl_Breakpoint_Location
            for loaded in session.generations {
                for location in loaded.breakpoint_locations {
                    if location.source_path != request.source_path ||
                       requested_line < location.source_start_line ||
                       requested_line > location.source_end_line {
                        continue
                    }
                    if has_requested_column {
                        if requested_line == location.source_start_line &&
                           requested_column < location.source_start_column {
                            continue
                        }
                        if requested_line == location.source_end_line &&
                           requested_column > location.source_end_column {
                            continue
                        }
                    }
                    append(&matches, location)
                }
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "breakpoint-locations",
                success = true,
                generation = generation,
                breakpoints = matches[:],
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            delete(matches)
            repl_delete_request(&request)
            continue
        }
        if request.op == "drop" {
            drop_message, dropped :=
                repl_session_drop_binding(
                    session,
                    request.name,
                    generation,
                )
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "drop",
                success = dropped,
                generation = generation,
                message = drop_message,
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = dropped,
                generation = generation,
                message = drop_message,
            })
            delete(drop_message)
            repl_delete_request(&request)
            continue
        }
        if request.op == "versions" {
            binding_index, found := repl_binding_index(session, request.name)
            if !found {
                unknown_message := fmt.tprintf("unknown REPL binding: %s", request.name)
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message = unknown_message,
                })
                delete(unknown_message)
            } else {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "versions",
                    success = true,
                    generation = generation,
                    versions = session.bindings[binding_index].versions[:],
                })
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = true,
                    generation = generation,
                })
            }
            repl_delete_request(&request)
            continue
        }
        if request.op == "definition-location" {
            binding, version, lookup_message, found :=
                repl_binding_version(
                    session,
                    request.name,
                    request.version,
                )
            if found {
                repl_emit_json_event(
                    repl_definition_location_event(
                        request.id,
                        generation,
                        binding,
                        version,
                    ),
                )
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = found,
                generation = generation,
                message = lookup_message,
            })
            delete(lookup_message)
            repl_delete_request(&request)
            continue
        }
        if request.op == "dependents" {
            if _, found := repl_binding_index(session, request.name); !found {
                unknown_message := fmt.tprintf("unknown REPL binding: %s", request.name)
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message = unknown_message,
                })
                delete(unknown_message)
            } else {
                dependents := repl_collect_dependents(session, request.name)
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "dependents",
                    success = true,
                    generation = generation,
                    bindings = dependents[:],
                })
                delete(dependents)
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = true,
                    generation = generation,
                })
            }
            repl_delete_request(&request)
            continue
        }
        if request.op == "refresh" || request.op == "refresh-dependents" {
            refresh_source, refresh_message: string
            refresh_ok: bool
            if request.op == "refresh" {
                refresh_source, refresh_message, refresh_ok =
                    repl_refresh_binding_source(session, request.name)
            } else {
                refresh_source, refresh_message, refresh_ok =
                    repl_refresh_dependents_source(session, request.name)
            }
            if !refresh_ok || refresh_source == "" {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = refresh_ok,
                    generation = generation,
                    message = refresh_message,
                })
                delete(refresh_source)
                delete(refresh_message)
                repl_delete_request(&request)
                continue
            }
            delete(request.source)
            request.source = refresh_source
            delete(refresh_message)
        }
        if request.op == "expand" || request.op == "macroexpand" {
            expansion, inspect_message, inspected := repl_inspect_source(
                input,
                request.source,
                session,
                request.op == "macroexpand",
                request.no_print,
            )
            if inspected {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "expansion",
                    success = true,
                    generation = generation,
                    text = expansion,
                })
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = inspected,
                generation = generation,
                message = inspect_message,
            })
            delete(expansion)
            delete(inspect_message)
            repl_delete_request(&request)
            continue
        }
        if request.op != "eval" &&
           request.op != "inspect" &&
           request.op != "inspect-page" &&
           request.op != "refresh" &&
           request.op != "refresh-dependents" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                message = "unsupported REPL request",
            })
            repl_delete_request(&request)
            continue
        }

        inspect_page := request.op == "inspect-page"
        inspect_only := request.op == "inspect" || inspect_page
        inspection_source_slot := ""
        inspection_source_type := ""
        inspection_page_shape := ""
        inspection_page_parent: ^Repl_Inspection
        request_index, request_has_index := request.index.(int)
        request_offset, request_has_offset := request.offset.(int)
        request_limit, request_has_limit := request.limit.(int)
        request_trace_limit, request_has_trace_limit :=
            request.trace_limit.(int)
        request_trace_value_limit,
        request_has_trace_value_limit :=
            request.trace_value_limit.(int)
        request_line, request_has_line := request.line.(int)
        request_column, request_has_column := request.column.(int)
        request_timeout_ms, request_has_timeout_ms :=
            request.timeout_ms.(int)
        if request.op == "inspect" &&
           request.handle != "" &&
           len(request.path) == 0 &&
           !request_has_index &&
           request.key_source == "" &&
           !request_has_offset &&
           !request_has_limit {
            prior_inspection, found :=
                repl_session_inspection(session, request.handle)
            emitted :=
                found &&
                repl_emit_cached_inspection(
                    request.id,
                    session,
                    prior_inspection,
                    generation,
                )
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = emitted,
                generation = generation,
                message =
                    "" if emitted else
                        ("inspection snapshot is unavailable" if found else
                            "unknown or expired inspection handle"),
            })
            repl_delete_request(&request)
            continue
        }
        if request_has_timeout_ms &&
           (request_timeout_ms <= 0 ||
            request_timeout_ms > REPL_MAX_TIMEOUT_MS) {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                generation = generation,
                message =
                    "timeout_ms must be between 1 and 3600000",
            })
            repl_delete_request(&request)
            continue
        }
        if request.trace &&
           request_has_trace_limit &&
           (request_trace_limit <= 0 ||
            request_trace_limit > REPL_MAX_TRACE_LIMIT) {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                generation = generation,
                message =
                    "trace_limit must be between 1 and 10000",
            })
            repl_delete_request(&request)
            continue
        }
        if request.trace_values && !request.trace {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                generation = generation,
                message = "trace_values requires trace",
            })
            repl_delete_request(&request)
            continue
        }
        if request_has_trace_value_limit &&
           (!request.trace_values ||
            request_trace_value_limit <= 0 ||
            request_trace_value_limit >
                REPL_MAX_TRACE_VALUE_LIMIT) {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                generation = generation,
                message =
                    "trace_value_limit requires trace_values and must be between 1 and 1000",
            })
            repl_delete_request(&request)
            continue
        }
        if inspect_only {
            if inspect_page {
                prior_inspection, found :=
                    repl_session_inspection(session, request.handle)
                valid_page := found &&
                              request_has_offset &&
                              request_offset >= 0 &&
                              request_has_limit &&
                              request_limit > 0 &&
                              request_limit <= REPL_MAX_PAGE_LIMIT &&
                              len(request.path) == 0 &&
                              !request_has_index &&
                              request.key_source == ""
                if valid_page {
                    prior_schema :=
                        repl_inspection_schema(
                            prior_inspection.ty,
                            prior_inspection.abi,
                        )
                    valid_page =
                        prior_schema.shape == "dynamic-array" ||
                        prior_schema.shape == "slice" ||
                        prior_schema.shape == "fixed-array" ||
                        prior_schema.shape == "map"
                    if valid_page {
                        inspection_page_shape =
                            strings.clone(prior_schema.shape)
                    }
                    delete(prior_schema.members)
                }
                if !valid_page {
                    message_text := "invalid inspection page request"
                    if !found {
                        message_text = "unknown or expired inspection handle"
                    }
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = request.id,
                        kind = "complete",
                        success = false,
                        generation = generation,
                        message = message_text,
                    })
                    repl_delete_request(&request)
                    continue
                }
                delete(request.source)
                request.source = strings.clone(prior_inspection.slot)
                inspection_source_slot = prior_inspection.slot
                inspection_source_type = prior_inspection.ty
                inspection_page_parent = prior_inspection
            } else if request.handle != "" {
                prior_inspection, found :=
                    repl_session_inspection(session, request.handle)
                child_source, valid_path := "", false
                if found {
                    prior_schema :=
                        repl_inspection_schema(
                            prior_inspection.ty,
                            prior_inspection.abi,
                        )
                    selector_matches_shape :=
                        (len(request.path) > 0 &&
                         prior_schema.shape == "struct") ||
                        (request_has_index &&
                         (prior_schema.shape == "dynamic-array" ||
                          prior_schema.shape == "slice" ||
                          prior_schema.shape == "fixed-array")) ||
                        (request.key_source != "" &&
                         prior_schema.shape == "map")
                    if selector_matches_shape {
                        child_source, valid_path =
                            repl_inspection_child_source(
                                prior_inspection.slot,
                                request.path[:],
                                request_index,
                                request_has_index,
                                request.key_source,
                            )
                    }
                    delete(prior_schema.members)
                }
                if !found || !valid_path {
                    message_text := "invalid inspection child path"
                    if !found {
                        message_text = "unknown or expired inspection handle"
                    }
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = request.id,
                        kind = "complete",
                        success = false,
                        generation = generation,
                        message = message_text,
                    })
                    delete(child_source)
                    repl_delete_request(&request)
                    continue
                }
                delete(request.source)
                request.source = child_source
                inspection_source_slot = prior_inspection.slot
                inspection_source_type = prior_inspection.ty
            } else if len(request.path) > 0 ||
                      request_has_index ||
                      request.key_source != "" {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message = "inspection path requires a handle",
                })
                repl_delete_request(&request)
                continue
            }
            if !inspect_page &&
               ((request_has_offset &&
                 request_offset < 0) ||
                (request_has_limit &&
                 (request_limit <= 0 ||
                  request_limit > REPL_MAX_PAGE_LIMIT))) {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message = "invalid inspection page bounds",
                })
                repl_delete_request(&request)
                continue
            }
            definitions := kvist.repl_persistent_definitions_source(request.source)
            has_definitions := definitions != ""
            delete(definitions)
            if has_definitions {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = false,
                    generation = generation,
                    message = "inspect accepts an expression, not persistent definitions",
                })
                repl_delete_request(&request)
                continue
            }
        }

        if request.op == "eval" &&
           !request.pause_before &&
           !request.trace &&
           !request.native_debug_symbols &&
           repl_source_is_unchanged_functions(
               input,
               request.source,
               request.source_path,
               session,
               request.defer_debug_values,
           ) {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = true,
                generation = generation,
            })
            repl_delete_request(&request)
            continue
        }

        generation += 1
        prior_worker_pid := worker.process.pid
        worker_message, worker_ready := repl_ensure_worker(worker)
        if !worker_ready {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                generation = generation,
                message = worker_message,
            })
            delete(worker_message)
            repl_delete_request(&request)
            continue
        }
        if worker.process.pid != prior_worker_pid {
            worker_epoch += 1
            repl_emit_json_event(
                repl_debug_event(
                    request.id,
                    "worker-replaced",
                    worker,
                    worker_epoch,
                    generation,
                ),
            )
        }
        inspection_handle, inspection_result_slot := "", ""
        if inspect_only && !inspect_page {
            inspection_handle, inspection_result_slot =
                repl_session_next_inspection(session)
        }
        inspection_abi := ""
        pause_id := ""
        if request.pause_before {
            pause_id = strings.clone(fmt.tprintf("pause-%d", generation))
        }
        nested_generation_counter := generation
        diagnostics: [dynamic]Repl_Diagnostic
        eval_timings := Repl_Eval_Timings{}
        output, message, evaluated := repl_handle_eval(
            input,
            request.source,
            session_dir,
            generation,
            request.no_print if !inspect_only else false,
            worker,
            session,
            request.source_path,
            request_line if request_has_line else 1,
            request_column if request_has_column else 1,
            pause_id,
            &reader,
            &request,
            inspect_only,
            &inspection_abi,
            inspection_source_slot,
            inspection_source_type,
            inspection_result_slot,
            request_offset if request_has_offset else 0,
            request_limit if request_has_limit else
                (REPL_DEFAULT_PAGE_LIMIT if inspect_only else 0),
            request.trace,
            request_trace_limit if request_has_trace_limit else
                REPL_DEFAULT_TRACE_LIMIT,
            request.trace_values,
            request_trace_value_limit if
                request_has_trace_value_limit else
                REPL_DEFAULT_TRACE_VALUE_LIMIT,
            &nested_generation_counter,
            false,
            0,
            request.op == "refresh" ||
                request.op == "refresh-dependents",
            nil,
            &diagnostics,
            request_timeout_ms if request_has_timeout_ms else 0,
            &eval_timings,
            request.native_debug_symbols,
            request.defer_debug_values,
            execution_mode,
        )
        generation_ran := evaluated
        aborted :=
            evaluated && message == REPL_EVALUATION_ABORTED_MESSAGE
        if aborted {
            evaluated = false
        }
        stderr_output := repl_worker_take_stderr(worker)
        inspection_output := output
        inspection_size, inspection_alignment := 0, 0
        inspection_has_layout := false
        if inspect_only && evaluated {
            inspection_output,
            inspection_size,
            inspection_alignment,
            inspection_has_layout =
                repl_parse_inspection_layout(output)
            if !inspection_has_layout {
                evaluated = false
                delete(message)
                message =
                    strings.clone(
                        "native inspection returned malformed layout metadata",
                    )
            }
        }
        delete(pause_id)
        if generation_ran {
            for loaded, loaded_index in session.generations {
                if loaded.generation == generation {
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = request.id,
                        kind = "generation-loaded",
                        success = true,
                        generation = generation,
                        generations =
                            session.generations[
                                loaded_index:loaded_index+1
                            ],
                    })
                    break
                }
            }
        }
        if inspect_page && evaluated {
            page_entries, page_total, parsed_page :=
                repl_parse_inspection_page(inspection_output)
            if parsed_page {
                page_schema :=
                    repl_inspection_schema(
                        inspection_page_parent.ty,
                        inspection_page_parent.abi,
                    )
                page_lifecycle :=
                    repl_type_lifecycle(
                        inspection_page_parent.ty,
                        inspection_page_parent.abi,
                    )
                inspection_event := Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "inspection-page",
                    success = true,
                    generation = generation,
                    handle = request.handle,
                    shape = inspection_page_shape,
                    ty = inspection_page_parent.ty,
                    abi = inspection_page_parent.abi,
                    element_type = page_schema.element_type,
                    key_type = page_schema.key_type,
                    value_type = page_schema.value_type,
                    length = &page_schema.length if page_schema.has_length else nil,
                    offset = Repl_Optional_Int(request_offset),
                    limit = Repl_Optional_Int(request_limit),
                    total = Repl_Optional_Int(page_total),
                    entries = page_entries[:],
                    lifecycle = Repl_Optional_Lifecycle(page_lifecycle),
                    owner_id = "repl-worker",
                    allocation_id = request.handle,
                    retained_owner_chain = []string{"repl-worker"},
                    size = Repl_Optional_Int(inspection_size),
                    alignment =
                        Repl_Optional_Int(inspection_alignment),
                }
                repl_annotate_inspection_definition(
                    &inspection_event,
                    session,
                    inspection_page_parent.abi,
                )
                repl_emit_json_event(inspection_event)
                delete(page_schema.members)
            } else {
                evaluated = false
                delete(message)
                message = strings.clone("native inspection page returned malformed output")
            }
            repl_inspection_entries_delete(page_entries[:])
        } else if inspect_only && evaluated {
            inspection_type := kvist.repl_result_type_from_abi(inspection_abi)
            retained_inspection :=
                inspection_type != "" && inspection_abi != ""
            if retained_inspection {
                repl_session_commit_inspection(
                    session,
                    inspection_handle,
                    inspection_result_slot,
                    inspection_type,
                    inspection_abi,
                    generation,
                )
            }
            inspection_schema :=
                repl_inspection_schema(inspection_type, inspection_abi)
            inspection_lifecycle :=
                repl_type_lifecycle(inspection_type, inspection_abi)
            inspection_entries: [dynamic]Repl_Inspection_Entry
            inspection_total := 0
            inspection_has_page := strings.has_prefix(
                inspection_output,
                REPL_PAGE_TOTAL_MARKER,
            )
            if inspection_has_page {
                page_parsed := false
                inspection_entries, inspection_total, page_parsed =
                    repl_parse_inspection_page(inspection_output)
                if !page_parsed {
                    evaluated = false
                    delete(message)
                    message =
                        strings.clone(
                            "native inspection page returned malformed output",
                        )
                }
            }
            if evaluated {
                if retained_inspection {
                    repl_session_cache_inspection(
                        session,
                        inspection_handle,
                        inspection_output,
                        inspection_size,
                        inspection_alignment,
                        "repl-worker",
                    )
                }
                inspection_event := Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "inspection",
                    success = true,
                    generation = generation,
                    text =
                        "" if inspection_has_page else inspection_output,
                    ty = inspection_type,
                    abi = inspection_abi,
                    handle = inspection_handle if retained_inspection else "",
                    path = request.path[:],
                    index = request.index,
                    key_source = request.key_source,
                    shape = inspection_schema.shape,
                    element_type = inspection_schema.element_type,
                    key_type = inspection_schema.key_type,
                    value_type = inspection_schema.value_type,
                    length = &inspection_schema.length if inspection_schema.has_length else nil,
                    members = inspection_schema.members[:],
                    offset =
                        Repl_Optional_Int(
                            request_offset if request_has_offset else 0,
                        ) if inspection_has_page else {},
                    limit =
                        Repl_Optional_Int(
                            request_limit if request_has_limit else
                                REPL_DEFAULT_PAGE_LIMIT,
                        ) if inspection_has_page else {},
                    total = Repl_Optional_Int(inspection_total) if inspection_has_page else {},
                    entries = inspection_entries[:],
                    lifecycle =
                        Repl_Optional_Lifecycle(inspection_lifecycle),
                    owner_id = "repl-worker",
                    allocation_id =
                        inspection_handle if retained_inspection else "",
                    retained_owner_chain =
                        []string{"repl-worker"} if
                            retained_inspection else nil,
                    size = Repl_Optional_Int(inspection_size),
                    alignment =
                        Repl_Optional_Int(inspection_alignment),
                }
                repl_annotate_inspection_definition(
                    &inspection_event,
                    session,
                    inspection_abi,
                )
                repl_emit_json_event(inspection_event)
            }
            repl_inspection_entries_delete(inspection_entries[:])
            delete(inspection_schema.members)
            delete(inspection_type)
        } else if output != "" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "output",
                success = true,
                generation = generation,
                stream = "stdout",
                text = output,
            })
        }
        if stderr_output != "" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "output",
                success = true,
                generation = generation,
                stream = "stderr",
                text = stderr_output,
            })
        }
        delete(inspection_handle)
        delete(inspection_result_slot)
        delete(inspection_page_shape)
        if output != "" {
            delete(output)
        }
        delete(stderr_output)
        delete(inspection_abi)
        if len(diagnostics) > 0 {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "diagnostics",
                success = evaluated,
                generation = generation,
                diagnostics = diagnostics[:],
            })
        }
        if !evaluated &&
           request_has_timeout_ms &&
           strings.has_prefix(
               message,
               "evaluation deadline exceeded",
           ) {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "deadline-exceeded",
                success = false,
                generation = generation,
                message = message,
                timeout_ms = Repl_Optional_Int(request_timeout_ms),
            })
        }
        if !evaluated &&
           worker.termination_kind == "crash" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "native-crash",
                success = false,
                generation = generation,
                message = message,
                failure_kind = "unexpected-worker-exit",
                exit_code =
                    Repl_Optional_Int(worker.exit_code) if
                        worker.has_exit_code else {},
            })
        }
        if aborted {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "aborted",
                success = true,
                generation = generation,
                message = REPL_EVALUATION_ABORTED_MESSAGE,
            })
        }
        timing_entries := repl_eval_timing_entries(&eval_timings)
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = "timings",
            success = evaluated,
            generation = generation,
            timings = timing_entries[:],
            generated_bytes =
                Repl_Optional_Int(eval_timings.generated_bytes) if
                    eval_timings.generated_bytes > 0 else {},
            native_cache_hit = eval_timings.native_cache_hit,
            frontend_cache_hit = eval_timings.frontend_cache_hit,
            execution_path = eval_timings.execution_path,
        })
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = "complete",
            success = evaluated,
            generation = generation,
            message = message,
            native_cache_hit = eval_timings.native_cache_hit,
            frontend_cache_hit = eval_timings.frontend_cache_hit,
            execution_path = eval_timings.execution_path,
        })
        if message != "" {
            delete(message)
        }
        repl_diagnostic_slice_delete(&diagnostics)
        generation = nested_generation_counter
        repl_delete_request(&request)
    }
}

repl_terminal_loop :: proc(
    input,
    session_dir: string,
    worker: ^Repl_Worker_Process,
    session: ^Repl_Session,
    execution_mode := Repl_Execution_Mode.Auto,
) -> int {
    reader := bufio.Reader{}
    bufio.reader_init(&reader, os.to_reader(os.stdin))
    defer bufio.reader_destroy(&reader)
    generation := 0

    fmt.println("Kvist native REPL")
    if execution_mode != .Auto {
        fmt.printfln(
            "Execution policy: %s",
            repl_execution_mode_name(execution_mode),
        )
    }
    fmt.println("Enter one expression per line; use :reset or :quit.")
    for {
        fmt.print("kvist=> ")
        _ = os.flush(os.stdout)
        raw, ok := repl_read_line(&reader)
        if !ok {
            fmt.println()
            return 0
        }
        line := strings.trim_space(repl_trim_line(raw))
        if line == "" {
            delete(raw)
            continue
        }
        if line == ":quit" {
            delete(raw)
            return 0
        }
        if line == ":reset" {
            repl_stop_worker(worker)
            next_worker, message, started := repl_start_worker()
            if !started {
                fmt.eprintln(message)
                delete(message)
                delete(raw)
                return 1
            }
            worker^ = next_worker
            generation = 0
            repl_session_clear(session)
            fmt.println("session reset")
            delete(raw)
            continue
        }

        if repl_source_is_unchanged_functions(
            input,
            line,
            input,
            session,
            true,
        ) {
            delete(raw)
            continue
        }

        generation += 1
        worker_message, worker_ready := repl_ensure_worker(worker)
        if !worker_ready {
            fmt.eprintln(worker_message)
            delete(worker_message)
            delete(raw)
            return 1
        }
        output, message, evaluated := repl_handle_eval(
            input,
            line,
            session_dir,
            generation,
            false,
            worker,
            session,
            defer_debug_values = true,
            execution_mode = execution_mode,
        )
        stderr_output := repl_worker_take_stderr(worker)
        if output != "" {
            fmt.print(output)
            delete(output)
        }
        if stderr_output != "" {
            fmt.eprint(stderr_output)
            delete(stderr_output)
        }
        if !evaluated {
            fmt.eprintln(message)
        }
        if message != "" {
            delete(message)
        }
        delete(raw)
    }
}

repl_attached_capabilities :: proc(
    capabilities: []olive_reload.Console_Capability,
) -> [dynamic]Repl_Attached_Capability {
    result: [dynamic]Repl_Attached_Capability
    for capability in capabilities {
        append(&result, Repl_Attached_Capability{
            name = capability.name,
            signature = capability.signature,
        })
    }
    return result
}

repl_attached_submit :: proc(
    endpoint,
    op,
    name,
    abi,
    input: string,
    counter: ^int,
) -> (
    response: olive_reload.Console_Response,
    message: string,
    ok: bool,
) {
    counter^ += 1
    request_id := fmt.aprintf(
        "%d-%d",
        time.time_to_unix_nano(time.now()),
        counter^,
    )
    defer delete(request_id)
    return olive_reload.console_submit(
        endpoint,
        olive_reload.Console_Request{
            protocol_version = olive_reload.CONSOLE_PROTOCOL_VERSION,
            id = request_id,
            op = op,
            name = name,
            signature = abi,
            input = input,
        },
    )
}

repl_attached_wait_for_continue :: proc(
    endpoint: string,
    protocol_reader: ^bufio.Reader,
    request: ^Repl_Request,
    pause_response: ^olive_reload.Console_Response,
    session: ^Repl_Session,
    frames: []Repl_Debug_Frame,
    counter: ^int,
) -> (
    response: olive_reload.Console_Response,
    message: string,
    ok: bool,
) {
    pause_id := pause_response.pause_id
    active_frames: []Repl_Debug_Frame
    for &frame, frame_index in frames {
        if frame.pause_id == pause_id {
            active_frames = frames[frame_index:frame_index+1]
            break
        }
    }
    retained_frames: [1]Repl_Debug_Frame
    has_retained_frame := false
    if len(active_frames) == 0 && session != nil {
        if retained_frame, found :=
            repl_session_debug_frame(session, pause_id); found {
            retained_frames[0] =
                repl_debug_frame_clone(retained_frame^)
            active_frames = retained_frames[:]
            has_retained_frame = true
        }
    }
    defer {
        if has_retained_frame {
            repl_debug_frame_delete(&retained_frames[0])
        }
    }
    fallback_frames: [1]Repl_Debug_Frame
    if len(active_frames) == 0 {
        source_line, has_source_line := request.line.(int)
        source_column, has_source_column := request.column.(int)
        fallback_frames[0] = Repl_Debug_Frame{
            frame_id = fmt.tprintf("frame-%s", pause_id),
            pause_id = pause_id,
            generation = pause_response.repl_generation,
            source_path = request.source_path,
            line = source_line if has_source_line else 1,
            column = source_column if has_source_column else 1,
            phase = "before-eval",
        }
        active_frames = fallback_frames[:]
    }
    value_index := 0
    if len(active_frames) > 0 {
        for &local in active_frames[0].locals {
            if value_index >= len(pause_response.pause_values) {
                break
            }
            delete(local.value)
            local.value =
                strings.clone(
                    pause_response.pause_values[value_index],
                )
            value_index += 1
            if local.element_type != "" ||
               (local.key_type != "" && local.value_type != "") {
                // Root rendering is safe and useful. Runtime collection
                // pages need the attached collection callback bridge, which
                // is a separate protocol layer.
                break
            }
            for &path in local.paths {
                if value_index >= len(pause_response.pause_values) {
                    break
                }
                delete(path.value)
                path.value =
                    strings.clone(
                        pause_response.pause_values[value_index],
                    )
                value_index += 1
            }
        }
        for collection in pause_response.pause_collections {
            already_present := false
            for current in active_frames[0].collections {
                if current.path == collection.path {
                    already_present = true
                    break
                }
            }
            if !already_present {
                append(
                    &active_frames[0].collections,
                    Repl_Debug_Collection{
                        path = strings.clone(collection.path),
                        shape = strings.clone(collection.shape),
                        element_type =
                            strings.clone(collection.element_type),
                        key_type = strings.clone(collection.key_type),
                        value_type =
                            strings.clone(collection.value_type),
                        descriptor = collection.descriptor,
                    },
                )
            }
        }
    }
    restarts: [5]Repl_Restart
    restart_count := 0
    restart_flags := pause_response.condition_restart_flags
    if pause_response.condition_type != "" {
        if restart_flags&REPL_RESTART_CONTINUE != 0 {
            restarts[restart_count] = Repl_Restart{
                name = "continue",
                label = "Continue from this safe point",
            }
            restart_count += 1
        }
        if restart_flags&REPL_RESTART_USE_VALUE != 0 &&
           pause_response.condition_value_type != "" {
            restarts[restart_count] = Repl_Restart{
                name = "use-value",
                label = "Replace the mutable local and continue",
                requires_value = true,
                value_type = pause_response.condition_value_type,
            }
            restart_count += 1
        }
        if restart_flags&REPL_RESTART_RETRY != 0 {
            restarts[restart_count] = Repl_Restart{
                name = "retry",
                label = "Retry the enclosing restart case",
            }
            restart_count += 1
        }
        if restart_flags&REPL_RESTART_SKIP != 0 {
            restarts[restart_count] = Repl_Restart{
                name = "skip",
                label = "Skip the rest of the enclosing restart case",
            }
            restart_count += 1
        }
        if restart_flags&REPL_RESTART_ABORT_OPERATION != 0 {
            restarts[restart_count] = Repl_Restart{
                name = "abort-operation",
                label = "Abort the enclosing debug operation",
            }
            restart_count += 1
        }
    }
    repl_emit_json_event(Repl_Event{
        protocol_version = REPL_PROTOCOL_VERSION,
        id = request.id,
        kind =
            "condition" if
                pause_response.condition_type != "" else "paused",
        success = true,
        generation = pause_response.repl_generation,
        pause_id = pause_id,
        message = pause_response.condition_message,
        condition_type = pause_response.condition_type,
        condition_data = pause_response.condition_data,
        restarts = restarts[:restart_count],
        frames = active_frames,
        attached = true,
        application_generation =
            Repl_Optional_Int(pause_response.generation),
        attached_generation =
            Repl_Optional_Int(pause_response.repl_generation),
    })
    for {
        raw, read_ok := repl_read_line(protocol_reader)
        if !read_ok {
            resume, resume_message, _ :=
                repl_attached_submit(
                    endpoint,
                    "debug-continue",
                    "",
                    "",
                    pause_id,
                    counter,
                )
            olive_reload.console_response_delete(&resume)
            if resume_message != "" do delete(resume_message)
            return response,
                   strings.clone(
                       "attached debug pause ended before continuation",
                   ),
                   false
        }
        line := repl_trim_line(raw)
        control := Repl_Request{}
        unmarshal_err :=
            json.unmarshal(transmute([]byte)line, &control)
        delete(raw)
        if unmarshal_err != nil {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                kind = "protocol-error",
                success = false,
                generation = pause_response.repl_generation,
                message = "invalid JSONL request while paused",
                attached = true,
            })
            repl_delete_request(&control)
            continue
        }
        pause_matches :=
            control.pause_id == "" ||
            control.pause_id == pause_id
        if control.op == "debug-frame" && pause_matches {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "debug-frame",
                success = len(active_frames) > 0,
                generation = pause_response.repl_generation,
                pause_id = pause_id,
                frames = active_frames,
                message =
                    "attached pause has no retained frame metadata" if
                        len(active_frames) == 0 else "",
                attached = true,
                application_generation =
                    Repl_Optional_Int(pause_response.generation),
                attached_generation =
                    Repl_Optional_Int(pause_response.repl_generation),
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = len(active_frames) > 0,
                generation = pause_response.repl_generation,
                pause_id = pause_id,
                attached = true,
            })
            repl_delete_request(&control)
            continue
        }
        if control.op == "debug-page" && pause_matches {
            requested_path := strings.trim_space(control.source)
            mapped_path := kvist.map_name(requested_path)
            collection_index := -1
            if len(active_frames) > 0 {
                for collection, index in
                    active_frames[0].collections {
                    if collection.path == requested_path ||
                       collection.path == mapped_path {
                        collection_index = index
                        break
                    }
                }
            }
            delete(mapped_path)
            offset, has_offset := control.offset.(int)
            if !has_offset do offset = 0
            limit, has_limit := control.limit.(int)
            if !has_limit do limit = REPL_DEFAULT_PAGE_LIMIT
            valid :=
                collection_index >= 0 &&
                offset >= 0 &&
                limit > 0 &&
                limit <= REPL_MAX_PAGE_LIMIT
            if !valid {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = control.id,
                    kind = "complete",
                    success = false,
                    generation = pause_response.repl_generation,
                    pause_id = pause_id,
                    message =
                        "collection path is not pageable in the active attached frame",
                    attached = true,
                })
                repl_delete_request(&control)
                continue
            }
            collection :=
                active_frames[0].collections[collection_index]
            page_input :=
                fmt.aprintf(
                    "%d\t%d\t%d",
                    collection.descriptor,
                    offset,
                    limit,
                )
            page_response, page_message, submitted :=
                repl_attached_submit(
                    endpoint,
                    "debug-page",
                    "",
                    "",
                    page_input,
                    counter,
                )
            delete(page_input)
            page_ok := submitted && page_response.success
            entries: [dynamic]Repl_Inspection_Entry
            discovered_collection_start := 0
            discovered_collections: []Repl_Debug_Collection
            if page_ok {
                for entry in page_response.page_entries {
                    append(&entries, Repl_Inspection_Entry{
                        index = Repl_Optional_Int(entry.index),
                        key = strings.clone(entry.key),
                        value = strings.clone(entry.value),
                    })
                }
                if len(active_frames) > 0 {
                    discovered_collection_start =
                        len(active_frames[0].collections)
                    for discovered in
                        page_response.page_collections {
                        append(
                            &active_frames[0].collections,
                            Repl_Debug_Collection{
                                path =
                                    strings.clone(discovered.path),
                                shape =
                                    strings.clone(discovered.shape),
                                element_type =
                                    strings.clone(
                                        discovered.element_type,
                                    ),
                                key_type =
                                    strings.clone(
                                        discovered.key_type,
                                    ),
                                value_type =
                                    strings.clone(
                                        discovered.value_type,
                                    ),
                                descriptor =
                                    discovered.descriptor,
                            },
                        )
                    }
                    discovered_collections =
                        active_frames[0].collections[
                            discovered_collection_start:
                        ]
                }
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = control.id,
                    kind = "debug-page",
                    success = true,
                    generation = pause_response.repl_generation,
                    pause_id = pause_id,
                    collection_path = collection.path,
                    shape = collection.shape,
                    element_type = collection.element_type,
                    key_type = collection.key_type,
                    value_type = collection.value_type,
                    offset = Repl_Optional_Int(offset),
                    limit = Repl_Optional_Int(limit),
                    total =
                        Repl_Optional_Int(page_response.page_total),
                    entries = entries[:],
                    collections = discovered_collections,
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(page_response.generation),
                    attached_generation =
                        Repl_Optional_Int(
                            page_response.repl_generation,
                        ),
                })
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = page_ok,
                generation = pause_response.repl_generation,
                pause_id = pause_id,
                message =
                    page_response.message if
                        submitted && page_response.message != "" else
                        page_message,
                attached = true,
            })
            repl_inspection_entries_delete(entries[:])
            olive_reload.console_response_delete(&page_response)
            if page_message != "" do delete(page_message)
            repl_delete_request(&control)
            continue
        }
        if control.op == "debug-restart" && pause_matches {
            restart_name := strings.trim_space(control.name)
            if restart_name == "" {
                restart_name = strings.trim_space(control.source)
            }
            restart_available :=
                pause_response.condition_type != "" &&
                ((restart_name == "continue" &&
                  restart_flags&REPL_RESTART_CONTINUE != 0) ||
                 (restart_name == "use-value" &&
                  restart_flags&REPL_RESTART_USE_VALUE != 0 &&
                  pause_response.condition_value_type != "") ||
                 (restart_name == "retry" &&
                  restart_flags&REPL_RESTART_RETRY != 0) ||
                 (restart_name == "skip" &&
                  restart_flags&REPL_RESTART_SKIP != 0) ||
                 (restart_name == "abort-operation" &&
                  restart_flags&
                      REPL_RESTART_ABORT_OPERATION != 0))
            restart_value := control.source
            value_valid := true
            if restart_name == "use-value" {
                restart_value = strings.trim_space(restart_value)
                switch pause_response.condition_value_type {
                case "int":
                    _, value_valid = strconv.parse_int(restart_value)
                case "bool":
                    value_valid =
                        restart_value == "true" ||
                        restart_value == "false"
                case "f32":
                    _, value_valid = strconv.parse_f32(restart_value)
                case "f64":
                    _, value_valid = strconv.parse_f64(restart_value)
                case "string":
                    restart_value = control.source
                case:
                    value_valid = false
                }
            }
            if !restart_available || !value_valid {
                message :=
                    "restart is not available for the active pause"
                if restart_available && !value_valid {
                    message = fmt.tprintf(
                        "use-value expects a valid %s value",
                        pause_response.condition_value_type,
                    )
                }
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = control.id,
                    kind = "complete",
                    success = false,
                    generation = pause_response.repl_generation,
                    pause_id = pause_id,
                    message = message,
                    attached = true,
                })
                repl_delete_request(&control)
                continue
            }
            restart_response, restart_message, submitted :=
                repl_attached_submit(
                    endpoint,
                    "debug-restart",
                    restart_name,
                    "",
                    restart_value,
                    counter,
                )
            restart_ok :=
                submitted && restart_response.success
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "restart-invoked",
                success = restart_ok,
                generation = pause_response.repl_generation,
                pause_id = pause_id,
                restart = restart_name,
                message =
                    restart_response.message if
                        submitted &&
                        restart_response.message != "" else
                        restart_message,
                attached = true,
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = restart_ok,
                generation = pause_response.repl_generation,
                pause_id = pause_id,
                attached = true,
            })
            olive_reload.console_response_delete(
                &restart_response,
            )
            if restart_message != "" do delete(restart_message)
            repl_delete_request(&control)
            if !restart_ok {
                continue
            }
            return olive_reload.console_receive(
                endpoint,
                pause_response.id,
            )
        }
        if (control.op == "debug-continue" ||
            control.op == "debug-step" ||
            control.op == "debug-step-over" ||
            control.op == "debug-step-out" ||
            control.op == "debug-abort") &&
           pause_matches {
            stepping := control.op != "debug-continue"
            aborting := control.op == "debug-abort"
            resume, resume_message, resumed :=
                repl_attached_submit(
                    endpoint,
                    control.op,
                    "",
                    "",
                    pause_id,
                    counter,
                )
            resume_ok := resumed && resume.success
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind =
                    "abort-requested" if aborting else
                    "stepping" if stepping else "resumed",
                success = resume_ok,
                generation = pause_response.repl_generation,
                pause_id = pause_id,
                message =
                    resume.message if
                        resumed && resume.message != "" else
                        resume_message,
                attached = true,
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = control.id,
                kind = "complete",
                success = resume_ok,
                generation = pause_response.repl_generation,
                pause_id = pause_id,
                attached = true,
            })
            olive_reload.console_response_delete(&resume)
            if resume_message != "" do delete(resume_message)
            repl_delete_request(&control)
            if !resume_ok {
                return response,
                       strings.clone(
                           "failed to control attached debug pause",
                       ),
                       false
            }
            return olive_reload.console_receive(
                endpoint,
                pause_response.id,
            )
        }
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = control.id,
            kind = "complete",
            success = false,
            generation = pause_response.repl_generation,
            pause_id = pause_id,
                message =
                    "attached REPL is paused; send debug-frame, debug-page, debug-restart, debug-step, debug-step-over, debug-step-out, debug-continue, or debug-abort with the active pause_id",
            attached = true,
        })
        repl_delete_request(&control)
    }
}

repl_attached_handle_eval :: proc(
    input,
    endpoint,
    session_dir: string,
    protocol_reader: ^bufio.Reader,
    request: ^Repl_Request,
    session: ^Repl_Session,
    generation: int,
    counter: ^int,
    inspect_only := false,
    inspect_page := false,
    inspection_source_slot := "",
    inspection_source_type := "",
    inspection_page_shape := "",
    inspection_page_parent: ^Repl_Inspection = nil,
    inspection_page_offset := 0,
    inspection_page_limit := 0,
) -> bool {
    compiled_source, normalize_err, normalized :=
        kvist.repl_normalize_source_path(
            input,
            request.source,
            request.source_path if request.source_path != "" else input,
        )
    if !normalized {
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = "complete",
            success = false,
            generation = generation,
            message = normalize_err.message,
            attached = true,
        })
        return false
    }
    defer delete(compiled_source)
    retained_source := repl_session_source(session)
    defer delete(retained_source)
    recent_result_types := repl_session_recent_result_types(session)
    defer delete(recent_result_types)
    breakpoint_locations: [dynamic]Repl_Breakpoint_Location
    defer repl_breakpoint_locations_delete(&breakpoint_locations)
    debug_frames: [dynamic]Repl_Debug_Frame
    defer repl_debug_frames_delete(&debug_frames)
    inspection_handle := ""
    inspection_result_slot := ""
    if inspect_only && !inspect_page {
        inspection_handle, inspection_result_slot =
            repl_session_next_inspection(session)
    }
    defer delete(inspection_handle)
    defer delete(inspection_result_slot)
    eval_line, has_eval_line := request.line.(int)
    eval_column, has_eval_column := request.column.(int)
    pause_id := ""
    if request.pause_before {
        pause_id = strings.clone(fmt.tprintf("pause-%d", generation))
    }
    defer delete(pause_id)
    persistent_definitions :=
        kvist.repl_persistent_definitions_source(compiled_source)
    defer delete(persistent_definitions)
    persistent_imports :=
        kvist.repl_persistent_imports_source(compiled_source)
    defer delete(persistent_imports)
    replace_resident_scalar_invokes :=
        session == nil || len(session.generations) == 0 ||
        persistent_definitions != "" || persistent_imports != "" ||
        !repl_latest_generation_dependencies_valid(session)
    library_path, emitted_source, diagnostic, compiled :=
        repl_compile_generation(
            input,
            compiled_source,
            retained_source,
            session_dir,
            session,
            generation,
            request.no_print,
            recent_result_types[:],
            request.source_path,
            eval_line if has_eval_line else 1,
            eval_column if has_eval_column else 1,
            &breakpoint_locations,
            &debug_frames,
            pause_id,
            inspect_only,
            inspection_source_slot,
            inspection_source_type,
            inspection_result_slot,
            inspection_page_offset,
            inspection_page_limit,
            capture_debug_values =
                request.trace || request.pause_before ||
                (!request.defer_debug_values &&
                 len(persistent_definitions) > 0),
            fast_native_build = request.defer_debug_values,
            allow_execution_plan = false,
            allow_resident_scalar = false,
        )
    if !compiled {
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = "complete",
            success = false,
            message = diagnostic,
            attached = true,
        })
        delete(diagnostic)
        return false
    }
    defer delete(library_path)
    defer delete(emitted_source)

    if request.trace {
        trace_limit := REPL_DEFAULT_TRACE_LIMIT
        if requested_limit, has_requested_limit :=
            request.trace_limit.(int); has_requested_limit {
            trace_limit = requested_limit
        }
        trace_value_limit := 0
        if request.trace_values {
            trace_value_limit = REPL_DEFAULT_TRACE_VALUE_LIMIT
            if requested_value_limit, has_requested_value_limit :=
                request.trace_value_limit.(int);
                has_requested_value_limit {
                trace_value_limit = requested_value_limit
            }
        }
        trace_input :=
            fmt.aprintf("%d\t%d", trace_limit, trace_value_limit)
        trace_response, trace_message, trace_configured :=
            repl_attached_submit(
                endpoint,
                "trace-next",
                "",
                "",
                trace_input,
                counter,
            )
        delete(trace_input)
        trace_ok := trace_configured && trace_response.success
        if !trace_ok {
            message := trace_message
            if trace_configured && trace_response.message != "" {
                message = trace_response.message
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                generation = generation,
                message = message,
                attached = true,
                application_generation =
                    Repl_Optional_Int(trace_response.generation),
            })
        }
        olive_reload.console_response_delete(&trace_response)
        if trace_message != "" do delete(trace_message)
        if !trace_ok {
            return false
        }
    }

    response, submit_message, submitted :=
        repl_attached_submit(
            endpoint,
            "load-generation",
            "",
            "",
            library_path,
            counter,
    )
    defer olive_reload.console_response_delete(&response)
    defer {
        if submit_message != "" do delete(submit_message)
    }
    trace_hotspots: [dynamic]Repl_Trace_Hotspot
    defer repl_trace_hotspots_delete(&trace_hotspots)
    previous_trace := Repl_Trace_Sample{}
    defer repl_trace_sample_delete(&previous_trace)
    has_previous_trace := false
    trace_points := 0
    trace_unattributed_ns := 0
    trace_truncated := false
    trace_truncated_at_ns := 0
    for submitted && response.success &&
        (response.output_stream != "" ||
         response.trace_kind != "" ||
         response.paused) {
        final_response: olive_reload.Console_Response
        final_message := ""
        final_ok := false
        if response.output_stream != "" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "output",
                success = true,
                generation = response.repl_generation,
                stream = response.output_stream,
                text = response.output,
                attached = true,
                application_generation =
                    Repl_Optional_Int(response.generation),
                attached_generation =
                    Repl_Optional_Int(response.repl_generation),
            })
            active_request_id := strings.clone(response.id)
            final_response, final_message, final_ok =
                olive_reload.console_receive(
                    endpoint,
                    active_request_id,
                )
            delete(active_request_id)
        } else if response.trace_kind != "" {
            switch response.trace_kind {
            case "trace":
                frame, frame_ok :=
                    repl_trace_frame(
                        session,
                        debug_frames[:],
                        response.trace_id,
                    )
                if has_previous_trace {
                    repl_trace_add_interval(
                        &trace_hotspots,
                        previous_trace,
                        response.trace_delta_ns,
                    )
                } else {
                    trace_unattributed_ns +=
                        max(response.trace_delta_ns, 0)
                }
                repl_trace_sample_set(
                    &previous_trace,
                    frame,
                    frame_ok,
                    response.trace_id,
                    response.trace_elapsed_ns,
                )
                has_previous_trace = true
                trace_points += 1
                event := Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "trace",
                    success = true,
                    generation = response.repl_generation,
                    trace_id = response.trace_id,
                    depth =
                        Repl_Optional_Int(response.trace_depth),
                    elapsed_ns =
                        Repl_Optional_Int(response.trace_elapsed_ns),
                    delta_ns =
                        Repl_Optional_Int(response.trace_delta_ns),
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(response.generation),
                    attached_generation =
                        Repl_Optional_Int(response.repl_generation),
                }
                if frame_ok {
                    event.source_path = frame.source_path
                    event.line = Repl_Optional_Int(frame.line)
                    event.column = Repl_Optional_Int(frame.column)
                }
                repl_emit_json_event(event)
            case "trace-values":
                frame, frame_ok :=
                    repl_trace_frame(
                        session,
                        debug_frames[:],
                        response.trace_id,
                    )
                if frame_ok &&
                   len(response.trace_values) <= len(frame.locals) {
                    values: [dynamic]Repl_Trace_Value
                    for rendered, value_index in
                        response.trace_values {
                        local := frame.locals[value_index]
                        append(&values, Repl_Trace_Value{
                            name = local.name,
                            ty = local.ty,
                            mutable = local.mutable,
                            ownership = local.ownership,
                            value = rendered,
                        })
                    }
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = request.id,
                        kind = "trace-values",
                        success = true,
                        generation = response.repl_generation,
                        trace_id = response.trace_id,
                        source_path = frame.source_path,
                        line = Repl_Optional_Int(frame.line),
                        column = Repl_Optional_Int(frame.column),
                        trace_values = values[:],
                        attached = true,
                        application_generation =
                            Repl_Optional_Int(response.generation),
                        attached_generation =
                            Repl_Optional_Int(
                                response.repl_generation,
                            ),
                    })
                    delete(values)
                }
            case "trace-values-limit":
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "trace-values-limit",
                    success = true,
                    generation = response.repl_generation,
                    message =
                        "instrumented trace value limit reached; later safe-point values were omitted",
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(response.generation),
                    attached_generation =
                        Repl_Optional_Int(response.repl_generation),
                })
            case "trace-limit":
                if has_previous_trace {
                    repl_trace_add_interval(
                        &trace_hotspots,
                        previous_trace,
                        response.trace_elapsed_ns -
                            previous_trace.elapsed_ns,
                    )
                    repl_trace_sample_delete(&previous_trace)
                    has_previous_trace = false
                }
                trace_truncated = true
                trace_truncated_at_ns =
                    max(response.trace_elapsed_ns, 0)
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "trace-limit",
                    success = true,
                    generation = response.repl_generation,
                    message =
                        "instrumented trace limit reached; remaining safe points were omitted",
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(response.generation),
                    attached_generation =
                        Repl_Optional_Int(response.repl_generation),
                })
            case "trace-end":
                total_ns := max(response.trace_elapsed_ns, 0)
                if trace_truncated {
                    trace_unattributed_ns +=
                        max(total_ns-trace_truncated_at_ns, 0)
                } else if has_previous_trace {
                    repl_trace_add_interval(
                        &trace_hotspots,
                        previous_trace,
                        total_ns-previous_trace.elapsed_ns,
                    )
                } else {
                    trace_unattributed_ns += total_ns
                }
                repl_trace_hotspots_sort(&trace_hotspots)
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "trace-summary",
                    success = true,
                    generation = response.repl_generation,
                    trace_points =
                        Repl_Optional_Int(trace_points),
                    trace_total_ns =
                        Repl_Optional_Int(total_ns),
                    trace_unattributed_ns =
                        Repl_Optional_Int(trace_unattributed_ns),
                    hotspots = trace_hotspots[:],
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(response.generation),
                    attached_generation =
                        Repl_Optional_Int(response.repl_generation),
                })
            }
            active_request_id := strings.clone(response.id)
            final_response, final_message, final_ok =
                olive_reload.console_receive(
                    endpoint,
                    active_request_id,
                )
            delete(active_request_id)
        } else {
            final_response, final_message, final_ok =
                repl_attached_wait_for_continue(
                    endpoint,
                    protocol_reader,
                    request,
                    &response,
                    session,
                    debug_frames[:],
                    counter,
                )
        }
        olive_reload.console_response_delete(&response)
        response = final_response
        if submit_message != "" do delete(submit_message)
        submit_message = final_message
        submitted = final_ok
    }
    loaded := submitted && response.success && !response.paused
    operation_message := submit_message
    if submitted && response.message != "" {
        operation_message = response.message
    }
    if !loaded {
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = "complete",
            success = false,
            generation = generation,
            message = operation_message,
            attached = true,
            application_generation =
                Repl_Optional_Int(response.generation),
        })
        return false
    }

    aborted := response.aborted
    loaded_generation := response.repl_generation
    generation_source_path, generation_library_path, generation_paths_ok :=
        repl_generation_paths(session_dir, generation)
    generation_map_path, generation_map_ok :=
        repl_generation_map_path(session_dir, generation)
    if generation_paths_ok {
        repl_session_record_generation_scalar_invokes(
            session,
            generation_source_path,
            replace_resident_scalar_invokes,
        )
    } else if replace_resident_scalar_invokes {
        repl_session_replace_scalar_invokes(session)
    }
    if generation_paths_ok && generation_map_ok {
        repl_session_commit_generation(
            session,
            loaded_generation,
            generation_source_path,
            generation_map_path,
            library_path,
            breakpoint_locations[:],
            debug_frames[:],
        )
    }
    if generation_paths_ok {
        delete(generation_source_path)
        delete(generation_library_path)
    }
    if generation_map_ok {
        delete(generation_map_path)
    }
    result_abi :=
        kvist.repl_inspection_result_abi(emitted_source) if inspect_only else
            kvist.repl_registered_result_abi(emitted_source)
    if !aborted && result_abi != "" && !inspect_page {
        result_ty := kvist.repl_result_type_from_abi(result_abi)
        if result_ty != "" && inspect_only {
            repl_session_commit_inspection(
                session,
                inspection_handle,
                inspection_result_slot,
                result_ty,
                result_abi,
                loaded_generation,
            )
        } else if result_ty != "" {
            repl_session_rotate_result(
                session,
                result_ty,
                result_abi,
                loaded_generation,
            )
        }
        delete(result_ty)
    }
    delete(result_abi)
    if !inspect_only {
        definitions :=
            kvist.repl_persistent_definitions_source(compiled_source)
        if definitions != "" {
            repl_session_commit(
                session,
                definitions,
                request.source,
                emitted_source,
                loaded_generation,
                request.source_path if request.source_path != "" else input,
                eval_line if has_eval_line else 1,
                eval_column if has_eval_column else 1,
                direct_scalar_invoke = request.defer_debug_values,
            )
        }
        delete(definitions)
    }

    generation_index := len(session.generations)-1
    repl_emit_json_event(Repl_Event{
        protocol_version = REPL_PROTOCOL_VERSION,
        id = request.id,
        kind = "generation-loaded",
        success = true,
        generation = loaded_generation,
        generations =
            session.generations[generation_index:generation_index+1],
        attached = true,
        application_generation =
            Repl_Optional_Int(response.generation),
        attached_generation =
            Repl_Optional_Int(loaded_generation),
    })
    if aborted {
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = "aborted",
            success = true,
            generation = loaded_generation,
            message = REPL_EVALUATION_ABORTED_MESSAGE,
            attached = true,
            application_generation =
                Repl_Optional_Int(response.generation),
            attached_generation =
                Repl_Optional_Int(loaded_generation),
        })
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = "complete",
            success = false,
            generation = loaded_generation,
            message = REPL_EVALUATION_ABORTED_MESSAGE,
            attached = true,
            application_generation =
                Repl_Optional_Int(response.generation),
            attached_generation =
                Repl_Optional_Int(loaded_generation),
        })
        return true
    }
    inspection_output := response.output
    inspection_size, inspection_alignment := 0, 0
    inspection_has_layout := false
    if inspect_only || inspect_page {
        inspection_output,
        inspection_size,
        inspection_alignment,
        inspection_has_layout =
            repl_parse_inspection_layout(response.output)
        if !inspection_has_layout {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                generation = loaded_generation,
                message =
                    "native inspection returned malformed layout metadata",
                attached = true,
                application_generation =
                    Repl_Optional_Int(response.generation),
                attached_generation =
                    Repl_Optional_Int(loaded_generation),
            })
            return false
        }
    }
    if inspect_page {
        page_entries, page_total, parsed_page :=
            repl_parse_inspection_page(inspection_output)
        if parsed_page && inspection_page_parent != nil {
            page_schema :=
                repl_inspection_schema(
                    inspection_page_parent.ty,
                    inspection_page_parent.abi,
                )
            page_lifecycle :=
                repl_type_lifecycle(
                    inspection_page_parent.ty,
                    inspection_page_parent.abi,
                )
            inspection_event := Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "inspection-page",
                success = true,
                generation = loaded_generation,
                handle = request.handle,
                shape = inspection_page_shape,
                ty = inspection_page_parent.ty,
                abi = inspection_page_parent.abi,
                element_type = page_schema.element_type,
                key_type = page_schema.key_type,
                value_type = page_schema.value_type,
                length =
                    &page_schema.length if page_schema.has_length else nil,
                offset = Repl_Optional_Int(inspection_page_offset),
                limit = Repl_Optional_Int(inspection_page_limit),
                total = Repl_Optional_Int(page_total),
                entries = page_entries[:],
                lifecycle = Repl_Optional_Lifecycle(page_lifecycle),
                owner_id = "attached-program",
                allocation_id = request.handle,
                retained_owner_chain = []string{"attached-program"},
                size = Repl_Optional_Int(inspection_size),
                alignment = Repl_Optional_Int(inspection_alignment),
                attached = true,
                application_generation =
                    Repl_Optional_Int(response.generation),
                attached_generation =
                    Repl_Optional_Int(loaded_generation),
            }
            repl_annotate_inspection_definition(
                &inspection_event,
                session,
                inspection_page_parent.abi,
            )
            repl_emit_json_event(inspection_event)
            delete(page_schema.members)
        } else {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                generation = loaded_generation,
                message =
                    "native inspection page returned malformed output",
                attached = true,
                application_generation =
                    Repl_Optional_Int(response.generation),
                attached_generation =
                    Repl_Optional_Int(loaded_generation),
            })
            repl_inspection_entries_delete(page_entries[:])
            return false
        }
        repl_inspection_entries_delete(page_entries[:])
    } else if inspect_only {
        inspection_abi :=
            kvist.repl_inspection_result_abi(emitted_source)
        inspection_type :=
            kvist.repl_result_type_from_abi(inspection_abi)
        inspection_schema :=
            repl_inspection_schema(inspection_type, inspection_abi)
        inspection_lifecycle :=
            repl_type_lifecycle(inspection_type, inspection_abi)
        inspection_entries: [dynamic]Repl_Inspection_Entry
        inspection_total := 0
        inspection_has_page :=
            strings.has_prefix(inspection_output, REPL_PAGE_TOTAL_MARKER)
        if inspection_has_page {
            page_parsed := false
            inspection_entries, inspection_total, page_parsed =
                repl_parse_inspection_page(inspection_output)
            if !page_parsed {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = false,
                    generation = loaded_generation,
                    message =
                        "native inspection page returned malformed output",
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(response.generation),
                    attached_generation =
                        Repl_Optional_Int(loaded_generation),
                })
                repl_inspection_entries_delete(inspection_entries[:])
                delete(inspection_schema.members)
                delete(inspection_type)
                delete(inspection_abi)
                return false
            }
        }
        repl_session_cache_inspection(
            session,
            inspection_handle,
            inspection_output,
            inspection_size,
            inspection_alignment,
            "attached-program",
        )
        inspection_event := Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = "inspection",
            success = inspection_type != "" && inspection_abi != "",
            generation = loaded_generation,
            text = "" if inspection_has_page else inspection_output,
            ty = inspection_type,
            abi = inspection_abi,
            handle = inspection_handle,
            path = request.path[:],
            index = request.index,
            key_source = request.key_source,
            shape = inspection_schema.shape,
            element_type = inspection_schema.element_type,
            key_type = inspection_schema.key_type,
            value_type = inspection_schema.value_type,
            length =
                &inspection_schema.length if
                    inspection_schema.has_length else nil,
            members = inspection_schema.members[:],
            offset =
                Repl_Optional_Int(inspection_page_offset) if
                    inspection_has_page else {},
            limit =
                Repl_Optional_Int(inspection_page_limit) if
                    inspection_has_page else {},
            total =
                Repl_Optional_Int(inspection_total) if
                    inspection_has_page else {},
            entries = inspection_entries[:],
            lifecycle = Repl_Optional_Lifecycle(inspection_lifecycle),
            owner_id = "attached-program",
            allocation_id = inspection_handle,
            retained_owner_chain = []string{"attached-program"},
            size = Repl_Optional_Int(inspection_size),
            alignment = Repl_Optional_Int(inspection_alignment),
            attached = true,
            application_generation =
                Repl_Optional_Int(response.generation),
            attached_generation =
                Repl_Optional_Int(loaded_generation),
        }
        repl_annotate_inspection_definition(
            &inspection_event,
            session,
            inspection_abi,
        )
        repl_emit_json_event(inspection_event)
        repl_inspection_entries_delete(inspection_entries[:])
        delete(inspection_schema.members)
        delete(inspection_type)
        delete(inspection_abi)
    } else if !request.no_print && response.output != "" {
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = "output",
            success = true,
            generation = loaded_generation,
            stream = "stdout",
            text = response.output,
            attached = true,
            application_generation =
                Repl_Optional_Int(response.generation),
            attached_generation =
                Repl_Optional_Int(loaded_generation),
        })
    }
    repl_emit_json_event(Repl_Event{
        protocol_version = REPL_PROTOCOL_VERSION,
        id = request.id,
        kind = "complete",
        success = true,
        generation = loaded_generation,
        attached = true,
        application_generation =
            Repl_Optional_Int(response.generation),
        attached_generation =
            Repl_Optional_Int(loaded_generation),
    })
    return true
}

repl_attached_protocol_loop :: proc(
    endpoint,
    input,
    session_dir: string,
    session: ^Repl_Session,
) -> int {
    reader := bufio.Reader{}
    bufio.reader_init(&reader, os.to_reader(os.stdin))
    defer bufio.reader_destroy(&reader)
    counter := 0
    artifact_generation := 0
    application_generation := 0
    handshake, handshake_message, connected :=
        repl_attached_submit(
            endpoint,
            "handshake",
            "",
            "",
            "",
            &counter,
        )
    if !connected || !handshake.success {
        message := handshake_message
        if connected && handshake.message != "" {
            message = handshake.message
        }
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            kind = "protocol-error",
            success = false,
            message = message,
            attached = true,
        })
        if handshake_message != "" {
            delete(handshake_message)
        }
        olive_reload.console_response_delete(&handshake)
        return 1
    }
    attached_capabilities :=
        repl_attached_capabilities(handshake.capabilities[:])
    artifact_generation = handshake.repl_generation
    application_generation = handshake.generation
    repl_emit_json_event(Repl_Event{
        protocol_version = REPL_PROTOCOL_VERSION,
        kind = "ready",
        success = true,
        generation = handshake.generation,
        attached = true,
        capabilities = []string{
            "attached-olive-console",
            "typed-host-capabilities",
            "checkpoint-scheduled-invocation",
            "repl-triggered-reload",
            "attached-native-generations",
            "attached-native-inspection",
            "attached-native-layout-metadata",
            "attached-inspection-definition-versions",
            "attached-cached-inspection-snapshots",
            "attached-logical-allocation-inventory",
            "attached-ownership-lifecycle-history",
            "attached-runtime-checkpoint-allocation-stats",
            "attached-generation-managed-allocation-stats",
            "attached-physical-allocation-inventory",
            "attached-physical-result-ownership-transfers",
            "attached-shared-data-physical-ownership",
            "attached-map-result-physical-ownership",
            "attached-binding-physical-ownership",
            "attached-pause-continue",
            "attached-source-stepping",
            "attached-collection-pages",
            "attached-nested-collection-pages",
            "attached-runtime-page-discovery",
            "attached-conditions-restarts",
            "attached-tracing",
            "attached-session-state-checkpoints",
        },
        attached_capabilities = attached_capabilities[:],
        attached_generation =
            Repl_Optional_Int(handshake.repl_generation),
    })
    delete(attached_capabilities)
    if handshake_message != "" {
        delete(handshake_message)
    }
    olive_reload.console_response_delete(&handshake)

    for {
        raw, read_ok := repl_read_line(&reader)
        if !read_ok {
            return 0
        }
        line := repl_trim_line(raw)
        request := Repl_Request{}
        unmarshal_err := json.unmarshal(transmute([]byte)line, &request)
        delete(raw)
        if unmarshal_err != nil {
            repl_delete_request(&request)
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                kind = "protocol-error",
                success = false,
                message = "invalid JSONL request",
                attached = true,
            })
            continue
        }
        if request.op == "close" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = true,
                attached = true,
            })
            repl_delete_request(&request)
            return 0
        }
        if _, has_timeout := request.timeout_ms.(int); has_timeout {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                generation = application_generation,
                message =
                    "timeout_ms is unavailable for attached applications; use cooperative restarts",
                attached = true,
                application_generation =
                    Repl_Optional_Int(application_generation),
                attached_generation =
                    Repl_Optional_Int(artifact_generation),
            })
            repl_delete_request(&request)
            continue
        }
        if repl_is_tooling_op(request.op) {
            logical_generation := 0
            if session != nil && len(session.generations) > 0 {
                logical_generation =
                    session.generations[len(session.generations)-1].generation
            }
            repl_emit_tooling_request(
                input,
                session,
                &request,
                logical_generation,
                attached = true,
                application_generation = application_generation,
            )
            repl_delete_request(&request)
            continue
        }
        if request.op == "bindings" ||
           request.op == "results" ||
           request.op == "allocations" ||
           request.op == "ownership-history" ||
           request.op == "generations" ||
           request.op == "versions" ||
           request.op == "definition-location" {
            logical_generation := 0
            if session != nil && len(session.generations) > 0 {
                logical_generation =
                    session.generations[len(session.generations)-1].generation
            }
            if session == nil {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = false,
                    generation = logical_generation,
                    message =
                        "attached session inventory requires a context file",
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(application_generation),
                    attached_generation =
                        Repl_Optional_Int(logical_generation),
                })
            } else if request.op == "bindings" {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "bindings",
                    success = true,
                    generation = logical_generation,
                    bindings = session.bindings[:],
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(application_generation),
                    attached_generation =
                        Repl_Optional_Int(logical_generation),
                })
            } else if request.op == "results" {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "results",
                    success = true,
                    generation = logical_generation,
                    results = session.results[:session.result_count],
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(application_generation),
                    attached_generation =
                        Repl_Optional_Int(logical_generation),
                })
            } else if request.op == "allocations" {
                allocations, known_bytes, known_count :=
                    repl_session_allocations(session)
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "allocations",
                    success = true,
                    generation = logical_generation,
                    allocations = allocations[:],
                    allocation_count =
                        Repl_Optional_Int(len(allocations)),
                    known_allocation_bytes =
                        Repl_Optional_Int(known_bytes),
                    known_allocation_count =
                        Repl_Optional_Int(known_count),
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(application_generation),
                    attached_generation =
                        Repl_Optional_Int(logical_generation),
                })
                delete(allocations)
            } else if request.op == "ownership-history" {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "ownership-history",
                    success = true,
                    generation = logical_generation,
                    ownership_events =
                        session.ownership_events[:],
                    ownership_event_count =
                        Repl_Optional_Int(
                            len(session.ownership_events),
                        ),
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(application_generation),
                    attached_generation =
                        Repl_Optional_Int(logical_generation),
                })
            } else if request.op == "generations" {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "generations",
                    success = true,
                    generation = logical_generation,
                    generations = session.generations[:],
                    attached = true,
                    application_generation =
                        Repl_Optional_Int(application_generation),
                    attached_generation =
                        Repl_Optional_Int(logical_generation),
                })
            } else if request.op == "versions" {
                binding_index, found :=
                    repl_binding_index(session, request.name)
                if found {
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = request.id,
                        kind = "versions",
                        success = true,
                        generation = logical_generation,
                        versions =
                            session.bindings[binding_index].versions[:],
                        attached = true,
                        application_generation =
                            Repl_Optional_Int(application_generation),
                        attached_generation =
                            Repl_Optional_Int(logical_generation),
                    })
                } else {
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = request.id,
                        kind = "complete",
                        success = false,
                        generation = logical_generation,
                        message = fmt.tprintf(
                            "unknown REPL binding: %s",
                            request.name,
                        ),
                        attached = true,
                        application_generation =
                            Repl_Optional_Int(application_generation),
                        attached_generation =
                            Repl_Optional_Int(logical_generation),
                    })
                    repl_delete_request(&request)
                    continue
                }
            } else {
                binding, version, lookup_message, found :=
                    repl_binding_version(
                        session,
                        request.name,
                        request.version,
                    )
                if found {
                    event :=
                        repl_definition_location_event(
                            request.id,
                            logical_generation,
                            binding,
                            version,
                        )
                    event.attached = true
                    event.application_generation =
                        Repl_Optional_Int(application_generation)
                    event.attached_generation =
                        Repl_Optional_Int(logical_generation)
                    repl_emit_json_event(event)
                } else {
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = request.id,
                        kind = "complete",
                        success = false,
                        generation = logical_generation,
                        message = lookup_message,
                        attached = true,
                        application_generation =
                            Repl_Optional_Int(application_generation),
                        attached_generation =
                            Repl_Optional_Int(logical_generation),
                    })
                    delete(lookup_message)
                    repl_delete_request(&request)
                    continue
                }
                delete(lookup_message)
            }
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = session != nil,
                generation = logical_generation,
                attached = true,
                application_generation =
                    Repl_Optional_Int(application_generation),
                attached_generation =
                    Repl_Optional_Int(logical_generation),
            })
            repl_delete_request(&request)
            continue
        }
        if request.op == "eval" ||
           request.op == "inspect" ||
           request.op == "inspect-page" {
            if input == "" || session_dir == "" || session == nil {
                repl_emit_json_event(Repl_Event{
                    protocol_version = REPL_PROTOCOL_VERSION,
                    id = request.id,
                    kind = "complete",
                    success = false,
                    message =
                        "attached eval requires a context file: kvist repl CONTEXT --attach ENDPOINT --protocol jsonl",
                    attached = true,
                })
            } else {
                _, cached_has_index :=
                    request.index.(int)
                _, cached_has_offset :=
                    request.offset.(int)
                _, cached_has_limit :=
                    request.limit.(int)
                if request.op == "inspect" &&
                   request.handle != "" &&
                   len(request.path) == 0 &&
                   !cached_has_index &&
                   request.key_source == "" &&
                   !cached_has_offset &&
                   !cached_has_limit {
                    logical_generation := 0
                    if len(session.generations) > 0 {
                        logical_generation =
                            session.generations[
                                len(session.generations)-1
                            ].generation
                    }
                    prior_inspection, found :=
                        repl_session_inspection(
                            session,
                            request.handle,
                        )
                    emitted :=
                        found &&
                        repl_emit_cached_inspection(
                            request.id,
                            session,
                            prior_inspection,
                            logical_generation,
                            attached = true,
                            application_generation =
                                application_generation,
                        )
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = request.id,
                        kind = "complete",
                        success = emitted,
                        generation = logical_generation,
                        message =
                            "" if emitted else
                                ("inspection snapshot is unavailable" if
                                    found else
                                    "unknown or expired inspection handle"),
                        attached = true,
                        application_generation =
                            Repl_Optional_Int(application_generation),
                        attached_generation =
                            Repl_Optional_Int(logical_generation),
                    })
                    repl_delete_request(&request)
                    continue
                }
                inspect_page := request.op == "inspect-page"
                inspect_only := request.op == "inspect" || inspect_page
                inspection_source_slot := ""
                inspection_source_type := ""
                inspection_page_shape := ""
                inspection_page_parent: ^Repl_Inspection
                request_index, request_has_index := request.index.(int)
                request_offset, request_has_offset := request.offset.(int)
                request_limit, request_has_limit := request.limit.(int)
                valid_inspection := true
                inspection_message := ""
                if inspect_page {
                    prior_inspection, found :=
                        repl_session_inspection(session, request.handle)
                    valid_inspection =
                        found &&
                        request_has_offset &&
                        request_offset >= 0 &&
                        request_has_limit &&
                        request_limit > 0 &&
                        request_limit <= REPL_MAX_PAGE_LIMIT &&
                        len(request.path) == 0 &&
                        !request_has_index &&
                        request.key_source == ""
                    if valid_inspection {
                        prior_schema :=
                            repl_inspection_schema(
                                prior_inspection.ty,
                                prior_inspection.abi,
                            )
                        valid_inspection =
                            prior_schema.shape == "dynamic-array" ||
                            prior_schema.shape == "slice" ||
                            prior_schema.shape == "fixed-array" ||
                            prior_schema.shape == "map"
                        if valid_inspection {
                            inspection_page_shape =
                                strings.clone(prior_schema.shape)
                        }
                        delete(prior_schema.members)
                    }
                    if valid_inspection {
                        delete(request.source)
                        request.source =
                            strings.clone(prior_inspection.slot)
                        inspection_source_slot = prior_inspection.slot
                        inspection_source_type = prior_inspection.ty
                        inspection_page_parent = prior_inspection
                    } else if !found {
                        inspection_message =
                            "unknown or expired inspection handle"
                    } else {
                        inspection_message =
                            "invalid inspection page request"
                    }
                } else if inspect_only && request.handle != "" {
                    prior_inspection, found :=
                        repl_session_inspection(session, request.handle)
                    child_source, valid_path := "", false
                    if found {
                        prior_schema :=
                            repl_inspection_schema(
                                prior_inspection.ty,
                                prior_inspection.abi,
                            )
                        selector_matches_shape :=
                            (len(request.path) > 0 &&
                             prior_schema.shape == "struct") ||
                            (request_has_index &&
                             (prior_schema.shape == "dynamic-array" ||
                              prior_schema.shape == "slice" ||
                              prior_schema.shape == "fixed-array")) ||
                            (request.key_source != "" &&
                             prior_schema.shape == "map")
                        if selector_matches_shape {
                            child_source, valid_path =
                                repl_inspection_child_source(
                                    prior_inspection.slot,
                                    request.path[:],
                                    request_index,
                                    request_has_index,
                                    request.key_source,
                                )
                        }
                        delete(prior_schema.members)
                    }
                    valid_inspection = found && valid_path
                    if valid_inspection {
                        delete(request.source)
                        request.source = child_source
                        inspection_source_slot = prior_inspection.slot
                        inspection_source_type = prior_inspection.ty
                    } else {
                        delete(child_source)
                        inspection_message =
                            "invalid inspection child path"
                        if !found {
                            inspection_message =
                                "unknown or expired inspection handle"
                        }
                    }
                } else if inspect_only &&
                          (len(request.path) > 0 ||
                           request_has_index ||
                           request.key_source != "") {
                    valid_inspection = false
                    inspection_message =
                        "inspection path requires a handle"
                }
                if inspect_only &&
                   !inspect_page &&
                   ((request_has_offset && request_offset < 0) ||
                    (request_has_limit &&
                     (request_limit <= 0 ||
                      request_limit > REPL_MAX_PAGE_LIMIT))) {
                    valid_inspection = false
                    inspection_message =
                        "invalid inspection page bounds"
                }
                if inspect_only && valid_inspection {
                    definitions :=
                        kvist.repl_persistent_definitions_source(
                            request.source,
                        )
                    if definitions != "" {
                        valid_inspection = false
                        inspection_message =
                            "inspect accepts an expression, not persistent definitions"
                    }
                    delete(definitions)
                }
                if !valid_inspection {
                    logical_generation := 0
                    if len(session.generations) > 0 {
                        logical_generation =
                            session.generations[
                                len(session.generations)-1
                            ].generation
                    }
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = request.id,
                        kind = "complete",
                        success = false,
                        generation = logical_generation,
                        message = inspection_message,
                        attached = true,
                        application_generation =
                            Repl_Optional_Int(application_generation),
                        attached_generation =
                            Repl_Optional_Int(logical_generation),
                    })
                } else if request.op == "eval" &&
                          !request.pause_before &&
                          !request.trace &&
                          !request.native_debug_symbols &&
                          repl_source_is_unchanged_functions(
                              input,
                              request.source,
                              request.source_path,
                              session,
                              request.defer_debug_values,
                          ) {
                    logical_generation := 0
                    if len(session.generations) > 0 {
                        logical_generation =
                            session.generations[
                                len(session.generations)-1
                            ].generation
                    }
                    repl_emit_json_event(Repl_Event{
                        protocol_version = REPL_PROTOCOL_VERSION,
                        id = request.id,
                        kind = "complete",
                        success = true,
                        generation = logical_generation,
                        attached = true,
                        application_generation =
                            Repl_Optional_Int(application_generation),
                        attached_generation =
                            Repl_Optional_Int(logical_generation),
                    })
                } else {
                    artifact_generation += 1
                    _ = repl_attached_handle_eval(
                        input,
                        endpoint,
                        session_dir,
                        &reader,
                        &request,
                        session,
                        artifact_generation,
                        &counter,
                        inspect_only,
                        inspect_page,
                        inspection_source_slot,
                        inspection_source_type,
                        inspection_page_shape,
                        inspection_page_parent,
                        request_offset if request_has_offset else 0,
                        request_limit if request_has_limit else
                            (REPL_DEFAULT_PAGE_LIMIT if inspect_only else 0),
                    )
                }
                delete(inspection_page_shape)
            }
            repl_delete_request(&request)
            continue
        }
        console_op := ""
        event_kind := ""
        switch request.op {
        case "attached-session", "capabilities", "reload-status":
            console_op = "status"
            event_kind = "attached-session"
        case "invoke-capability":
            console_op = "invoke"
            event_kind = "capability-result"
        case "reload":
            console_op = "reload"
            event_kind = "reload-requested"
        case "reset":
            console_op = "reset-session"
            event_kind = "attached-reset"
        case "checkpoint":
            console_op = "checkpoint"
            event_kind = "checkpoint-saved"
        case "checkpoint-restore":
            console_op = "checkpoint-restore"
            event_kind = "checkpoint-restored"
        case "checkpoint-drop":
            console_op = "checkpoint-drop"
            event_kind = "checkpoint-dropped"
        case "checkpoints":
            console_op = "checkpoints"
            event_kind = "checkpoints"
        case "runtime-allocations":
            console_op = "runtime-allocations"
            event_kind = "runtime-allocations"
        case "physical-allocations":
            console_op = "physical-allocations"
            event_kind = "physical-allocations"
        case:
        }
        if console_op == "" {
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = false,
                message =
                    "attached sessions accept eval, inspect, inspect-page, checkpoint, checkpoints, checkpoint-restore, checkpoint-drop, runtime-allocations, physical-allocations, reset, attached-session, capabilities, reload-status, invoke-capability, reload, or close",
                attached = true,
            })
            repl_delete_request(&request)
            continue
        }
        response, submit_message, submitted :=
            repl_attached_submit(
                endpoint,
                console_op,
                request.name,
                request.abi,
                request.source,
                &counter,
            )
        operation_ok := submitted && response.success
        if submitted {
            application_generation = response.generation
        }
        operation_message := submit_message
        if submitted && response.message != "" {
            operation_message = response.message
        }
        response_capabilities :=
            repl_attached_capabilities(response.capabilities[:])
        response_checkpoints: [dynamic]Repl_Checkpoint
        for checkpoint in response.checkpoints {
            append(&response_checkpoints, Repl_Checkpoint{
                name = checkpoint.name,
                bindings = checkpoint.bindings,
            })
        }
        response_physical_allocations:
            [dynamic]Repl_Physical_Allocation
        for allocation in response.physical_allocations {
            primary_owner :=
                repl_physical_owner_id(
                    int(allocation.owner_kind),
                    allocation.owner_generation,
                    allocation.owner_name,
                )
            owner_chain := make(
                [dynamic]string,
                0,
                1 + len(
                    allocation.retained_result_generations,
                ) + len(allocation.retained_binding_owners),
            )
            append(
                &owner_chain,
                strings.clone(primary_owner),
            )
            for retained_generation in
                allocation.retained_result_generations {
                append(
                    &owner_chain,
                    fmt.aprintf(
                        "result:g%d",
                        retained_generation,
                    ),
                )
            }
            for owner in allocation.retained_binding_owners {
                append(
                    &owner_chain,
                    repl_physical_owner_id(
                        int(
                            kvist_repl.Worker_Managed_Owner_Kind.Binding,
                        ),
                        owner.generation,
                        owner.name,
                    ),
                )
            }
            append(
                &response_physical_allocations,
                Repl_Physical_Allocation{
                    allocation_id =
                        fmt.aprintf(
                            "managed:%d",
                            allocation.allocation_id,
                        ),
                    owner_id = primary_owner,
                    kind = strings.clone("managed"),
                    size = allocation.size,
                    alignment = allocation.alignment,
                    generation = allocation.generation,
                    retained_owner_chain = owner_chain,
                },
            )
        }
        response_physical_transfers:
            [dynamic]Repl_Physical_Transfer
        for transfer in response.physical_transfers {
            append(
                &response_physical_transfers,
                Repl_Physical_Transfer{
                    sequence = transfer.sequence,
                    allocation_id =
                        fmt.aprintf(
                            "managed:%d",
                            transfer.allocation_id,
                        ),
                    owner_from =
                        repl_physical_owner_id(
                            int(transfer.owner_from_kind),
                            transfer.owner_from_generation,
                            transfer.owner_from_name,
                        ),
                    owner_to =
                        repl_physical_owner_id(
                            int(transfer.owner_to_kind),
                            transfer.owner_to_generation,
                            transfer.owner_to_name,
                        ),
                    generation = transfer.generation,
                    action = strings.clone(
                        "retained" if transfer.action ==
                            .Retained else "transferred",
                    ),
                    reason = strings.clone(
                        ("shared binding allocation retained" if
                            transfer.action == .Retained else
                            "exclusive binding allocation transferred") if
                            transfer.owner_to_kind == .Binding else
                        ("shared Data result retained" if
                            transfer.action == .Retained else
                            "exclusive result allocation transferred"),
                    ),
                },
            )
        }
        checkpoint_mutation :=
            request.op == "checkpoint" ||
            request.op == "checkpoint-restore" ||
            request.op == "checkpoint-drop"
        checkpoint_operation :=
            checkpoint_mutation || request.op == "checkpoints"
        runtime_allocation_operation :=
            request.op == "runtime-allocations"
        physical_allocation_operation :=
            request.op == "physical-allocations"
        event_generation :=
            response.repl_generation if
                checkpoint_operation ||
                runtime_allocation_operation ||
                physical_allocation_operation else
                response.generation
        if request.op == "reset" && operation_ok {
            if session != nil {
                repl_session_clear(session)
            }
        }
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = event_kind,
            success = operation_ok,
            generation = event_generation,
            message = operation_message,
            text = response.output,
            checkpoint =
                request.name if checkpoint_mutation else "",
            checkpoint_bindings =
                Repl_Optional_Int(response.checkpoint_bindings) if
                    checkpoint_mutation else {},
            checkpoints = response_checkpoints[:],
            runtime_live_allocations =
                Repl_Optional_Int(
                    response.runtime_live_allocations,
                ) if runtime_allocation_operation else {},
            runtime_live_bytes =
                Repl_Optional_Int(
                    response.runtime_live_bytes,
                ) if runtime_allocation_operation else {},
            runtime_total_allocations =
                Repl_Optional_Int(
                    response.runtime_total_allocations,
                ) if runtime_allocation_operation else {},
            runtime_total_allocated_bytes =
                Repl_Optional_Int(
                    response.runtime_total_allocated_bytes,
                ) if runtime_allocation_operation else {},
            runtime_total_frees =
                Repl_Optional_Int(
                    response.runtime_total_frees,
                ) if runtime_allocation_operation else {},
            runtime_total_freed_bytes =
                Repl_Optional_Int(
                    response.runtime_total_freed_bytes,
                ) if runtime_allocation_operation else {},
            managed_live_allocations =
                Repl_Optional_Int(
                    response.managed_live_allocations,
                ) if runtime_allocation_operation else {},
            managed_live_bytes =
                Repl_Optional_Int(
                    response.managed_live_bytes,
                ) if runtime_allocation_operation else {},
            managed_peak_bytes =
                Repl_Optional_Int(
                    response.managed_peak_bytes,
                ) if runtime_allocation_operation else {},
            managed_total_allocations =
                Repl_Optional_Int(
                    response.managed_total_allocations,
                ) if runtime_allocation_operation else {},
            managed_total_allocated_bytes =
                Repl_Optional_Int(
                    response.managed_total_allocated_bytes,
                ) if runtime_allocation_operation else {},
            managed_total_frees =
                Repl_Optional_Int(
                    response.managed_total_frees,
                ) if runtime_allocation_operation else {},
            managed_total_freed_bytes =
                Repl_Optional_Int(
                    response.managed_total_freed_bytes,
                ) if runtime_allocation_operation else {},
            physical_allocations =
                response_physical_allocations[:],
            physical_allocation_count =
                Repl_Optional_Int(
                    len(response_physical_allocations),
                ) if physical_allocation_operation else {},
            physical_transfers =
                response_physical_transfers[:],
            physical_transfer_count =
                Repl_Optional_Int(
                    len(response_physical_transfers),
                ) if physical_allocation_operation else {},
            attached = true,
            attached_capabilities = response_capabilities[:],
            reload_requested = response.reload_requested,
            application_generation =
                Repl_Optional_Int(response.generation),
            attached_generation =
                Repl_Optional_Int(response.repl_generation),
        })
        delete(response_checkpoints)
        repl_physical_allocation_slice_delete(
            &response_physical_allocations,
        )
        repl_physical_transfer_slice_delete(
            &response_physical_transfers,
        )
        if request.op == "reload" && operation_ok {
            requested_generation := response.generation
            delete(response_capabilities)
            if submit_message != "" {
                delete(submit_message)
            }
            olive_reload.console_response_delete(&response)

            replacement, replacement_message, replacement_submitted :=
                repl_attached_submit(
                    endpoint,
                    "status",
                    "",
                    "",
                    "",
                    &counter,
                )
            replacement_ok :=
                replacement_submitted &&
                replacement.success &&
                replacement.generation > requested_generation
            if replacement_submitted {
                application_generation = replacement.generation
            }
            completion_message := replacement_message
            if replacement_submitted && replacement.message != "" {
                completion_message = replacement.message
            }
            if replacement_submitted &&
               replacement.success &&
               replacement.generation <= requested_generation {
                completion_message =
                    "reload reached a checkpoint without advancing the application generation"
            }
            replacement_capabilities :=
                repl_attached_capabilities(replacement.capabilities[:])
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "reload-complete",
                success = replacement_ok,
                generation = replacement.generation,
                message = completion_message,
                attached = true,
                application_generation =
                    Repl_Optional_Int(replacement.generation),
                attached_generation =
                    Repl_Optional_Int(replacement.repl_generation),
                attached_capabilities = replacement_capabilities[:],
            })
            repl_emit_json_event(Repl_Event{
                protocol_version = REPL_PROTOCOL_VERSION,
                id = request.id,
                kind = "complete",
                success = replacement_ok,
                generation = replacement.generation,
                message = completion_message,
                attached = true,
                application_generation =
                    Repl_Optional_Int(replacement.generation),
                attached_generation =
                    Repl_Optional_Int(replacement.repl_generation),
            })
            delete(replacement_capabilities)
            if replacement_message != "" {
                delete(replacement_message)
            }
            olive_reload.console_response_delete(&replacement)
            repl_delete_request(&request)
            continue
        }
        repl_emit_json_event(Repl_Event{
            protocol_version = REPL_PROTOCOL_VERSION,
            id = request.id,
            kind = "complete",
            success = operation_ok,
            generation = event_generation,
            message = operation_message,
            attached = true,
            application_generation =
                Repl_Optional_Int(response.generation),
            attached_generation =
                Repl_Optional_Int(response.repl_generation),
        })
        delete(response_capabilities)
        if submit_message != "" {
            delete(submit_message)
        }
        olive_reload.console_response_delete(&response)
        repl_delete_request(&request)
    }
}

repl_attached_command :: proc(
    endpoint,
    input: string,
    protocol_jsonl: bool,
) -> int {
    if !protocol_jsonl {
        fmt.eprintln("attached REPL currently requires --protocol jsonl")
        return 2
    }
    if endpoint == "" || !os.exists(endpoint) || !os.is_dir(endpoint) {
        fmt.eprintln("attached REPL endpoint does not exist: ", endpoint)
        return 1
    }
    if input == "" {
        return repl_attached_protocol_loop(endpoint, "", "", nil)
    }
    if !os.exists(input) {
        fmt.eprintln("REPL context file does not exist: ", input)
        return 1
    }
    session_dir, temp_err :=
        os.make_directory_temp(
            "",
            "kvist-attached-repl-*",
            context.allocator,
        )
    if temp_err != nil {
        fmt.eprintln("failed to create attached REPL session directory")
        return 1
    }
    defer {
        _ = os.remove_all(session_dir)
        delete(session_dir)
    }
    session := Repl_Session{}
    defer repl_session_delete(&session)
    return repl_attached_protocol_loop(
        endpoint,
        input,
        session_dir,
        &session,
    )
}

repl_command :: proc(
    input: string,
    protocol_jsonl: bool,
    execution_mode := Repl_Execution_Mode.Auto,
) -> int {
    if !os.exists(input) {
        fmt.eprintln("REPL context file does not exist: ", input)
        return 1
    }
    session_dir, temp_err := os.make_directory_temp("", "kvist-repl-*", context.allocator)
    if temp_err != nil {
        fmt.eprintln("failed to create REPL session directory")
        return 1
    }
    defer {
        _ = os.remove_all(session_dir)
        delete(session_dir)
    }

    worker, start_message, started := repl_start_worker()
    if !started {
        fmt.eprintln(start_message)
        delete(start_message)
        return 1
    }
    defer repl_stop_worker(&worker)
    session := Repl_Session{}
    defer repl_session_delete(&session)

    if protocol_jsonl {
        return repl_protocol_loop(
            input,
            session_dir,
            &worker,
            &session,
            execution_mode,
        )
    }
    return repl_terminal_loop(
        input,
        session_dir,
        &worker,
        &session,
        execution_mode,
    )
}

repl_eval_once :: proc(
    input,
    source: string,
    no_print: bool,
) -> int {
    if !os.exists(input) {
        fmt.eprintln("eval context file does not exist: ", input)
        return 1
    }
    session_dir, temp_err :=
        os.make_directory_temp(
            "",
            "kvist-eval-session-*",
            context.allocator,
        )
    if temp_err != nil {
        fmt.eprintln("failed to create eval session directory")
        return 1
    }
    defer {
        _ = os.remove_all(session_dir)
        delete(session_dir)
    }

    worker, start_message, started := repl_start_worker()
    if !started {
        fmt.eprintln(start_message)
        delete(start_message)
        return 1
    }
    defer repl_stop_worker(&worker)
    session := Repl_Session{}
    defer repl_session_delete(&session)

    warning_text := ""
    defer delete(warning_text)
    output, message, evaluated :=
        repl_handle_eval(
            input,
            source,
            session_dir,
            1,
            no_print,
            &worker,
            &session,
            input,
            compile_warning_text = &warning_text,
        )
    stderr_output := repl_worker_take_stderr(&worker)
    if warning_text != "" {
        fmt.eprint(warning_text)
    }
    if output != "" {
        fmt.print(output)
        delete(output)
    }
    if stderr_output != "" {
        fmt.eprint(stderr_output)
        delete(stderr_output)
    }
    if message != "" {
        if !evaluated {
            fmt.eprint(message)
            if message[len(message)-1] != '\n' {
                fmt.eprintln()
            }
        }
        delete(message)
    }
    return 0 if evaluated else 1
}

parse_repl_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }
    input := os.args[2]
    attached_endpoint := ""
    attached := input == "--attach"
    attached_input := ""
    if attached {
        if len(os.args) < 4 {
            print_usage()
            exit_with_timing(2)
        }
        attached_endpoint = os.args[3]
    } else if len(os.args) >= 5 && os.args[3] == "--attach" {
        attached = true
        attached_input = input
        attached_endpoint = os.args[4]
    }
    protocol_jsonl := false
    execution_mode := Repl_Execution_Mode.Auto
    i := 5 if attached_input != "" else (4 if attached else 3)
    for i < len(os.args) {
        switch os.args[i] {
        case "--protocol":
            if i+1 >= len(os.args) || os.args[i+1] != "jsonl" {
                print_usage()
                exit_with_timing(2)
            }
            protocol_jsonl = true
            i += 2
        case "--execution":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            parsed_mode, parsed :=
                repl_execution_mode_parse(os.args[i+1])
            if !parsed {
                fmt.eprintln(
                    "--execution must be auto, resident, native-adapter, " +
                    "native-reuse, or native",
                )
                exit_with_timing(2)
            }
            execution_mode = parsed_mode
            i += 2
        case:
            print_usage()
            exit_with_timing(2)
        }
    }
    if attached {
        if execution_mode != .Auto {
            fmt.eprintln(
                "--execution applies only to a standalone REPL; " +
                "attached evaluation is native",
            )
            exit_with_timing(2)
        }
        exit_with_timing(
            repl_attached_command(
                attached_endpoint,
                attached_input,
                protocol_jsonl,
            ),
        )
    }
    exit_with_timing(
        repl_command(input, protocol_jsonl, execution_mode),
    )
}
