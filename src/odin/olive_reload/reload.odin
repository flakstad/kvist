package olive_reload

import "base:runtime"
import "core:dynlib"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:time"
import kvist_repl "../kvist_repl"

MANIFEST_API_VERSION :: u32(1)

Core_Symbols :: struct {
  api_version: ^u32 `dynlib:"olive_reload_api_version"`,
  state_size:  proc "c" () -> int `dynlib:"olive_reload_state_size"`,
  state_align: proc "c" () -> int `dynlib:"olive_reload_state_align"`,
  on_load:     proc "c" (state: rawptr, is_reload: bool) `dynlib:"olive_reload_on_load"`,
  on_unload:   proc "c" (state: rawptr) `dynlib:"olive_reload_on_unload"`,
  __handle:    dynlib.Library,
}

Reload_Event_Kind :: enum {
  Started,
  Reloaded,
  Restarted,
  Resource_Changed,
  Reload_Failed,
}

Reload_Event :: struct {
  kind:       Reload_Event_Kind,
  generation: int,
  message:    string,
}

Run_Host :: struct {
  exit_requested:   bool,
  session:          rawptr,
  checkpoint_error: string,
  console:          rawptr,
  console_reload_requested: bool,
}

CONSOLE_PROTOCOL_VERSION :: 1
CONSOLE_ENDPOINT_ENV :: "KVIST_REPL_ENDPOINT"
CONSOLE_REQUEST_TIMEOUT :: 30 * time.Second
CONSOLE_REQUEST_ID_LIMIT :: 128
CONSOLE_REQUEST_BYTES_LIMIT :: 16 * 1024 * 1024

Console_Capability_Handler :: proc(
  ctx: rawptr,
  input: string,
) -> (output, message: string, ok: bool)

Console_Capability :: struct {
  name:      string,
  signature: string,
  ctx:       rawptr `json:"-"`,
  handler:   Console_Capability_Handler `json:"-"`,
}

Console_Host_State :: struct {
  allocator:    runtime.Allocator,
  endpoint:     string,
  capabilities: [dynamic]Console_Capability,
  repl_worker:  kvist_repl.Worker,
  host:         ^Run_Host,
  active_request_id: string,
  repl_paused:  bool,
  repl_pause_id: string,
  repl_pause_values: [dynamic]string,
  repl_pause_collections: kvist_repl.Attached_Collection_State,
  repl_pause_collection_views: [dynamic]Console_Debug_Collection,
  repl_page_entries: [dynamic]Console_Page_Entry,
  repl_condition_pause_id: string,
  repl_condition_type: string,
  repl_condition_message: string,
  repl_condition_data: string,
  repl_condition_value_type: string,
  repl_condition_restart_flags: u32,
  repl_restart_name: string,
  repl_restart_value: string,
  repl_checkpoint_views: [dynamic]Console_Checkpoint,
  repl_physical_allocation_views: [dynamic]Console_Physical_Allocation,
  repl_physical_transfer_views: [dynamic]Console_Physical_Transfer,
  repl_checkpoint_message: string,
}

Console_Debug_Collection :: struct {
  path:         string,
  shape:        string,
  element_type: string `json:",omitempty"`,
  key_type:     string `json:",omitempty"`,
  value_type:   string `json:",omitempty"`,
  descriptor:   int,
}

Console_Page_Entry :: struct {
  index: int,
  key:   string `json:",omitempty"`,
  value: string,
}

Console_Checkpoint :: struct {
  name:     string,
  bindings: int,
}

Console_Physical_Allocation :: struct {
  allocation_id: int,
  size:          int,
  alignment:     int,
  generation:    int,
  owner_kind:    kvist_repl.Worker_Managed_Owner_Kind,
  owner_generation: int,
  owner_name: string,
  retained_result_generations: [dynamic]int,
  retained_binding_owners:
    [dynamic]kvist_repl.Worker_Managed_Binding_Owner,
}

Console_Physical_Transfer :: struct {
  sequence: int,
  allocation_id: int,
  generation: int,
  owner_from_kind: kvist_repl.Worker_Managed_Owner_Kind,
  owner_from_generation: int,
  owner_from_name: string,
  owner_to_kind: kvist_repl.Worker_Managed_Owner_Kind,
  owner_to_generation: int,
  owner_to_name: string,
  action: kvist_repl.Worker_Managed_Transfer_Action,
}

Console_Request :: struct {
  protocol_version: int,
  id:               string,
  op:               string,
  name:             string `json:",omitempty"`,
  signature:        string `json:",omitempty"`,
  input:            string `json:",omitempty"`,
}

Console_Response :: struct {
  protocol_version: int,
  id:               string,
  success:          bool,
  generation:       int,
  message:          string `json:",omitempty"`,
  output:           string `json:",omitempty"`,
  output_stream:    string `json:",omitempty"`,
  capabilities:     []Console_Capability `json:",omitempty"`,
  reload_requested: bool `json:",omitempty"`,
  repl_generation:  int `json:",omitempty"`,
  paused:           bool `json:",omitempty"`,
  aborted:          bool `json:",omitempty"`,
  pause_id:         string `json:",omitempty"`,
  pause_values:     []string `json:",omitempty"`,
  pause_collections: []Console_Debug_Collection `json:",omitempty"`,
  page_collections: []Console_Debug_Collection `json:",omitempty"`,
  page_entries:     []Console_Page_Entry `json:",omitempty"`,
  page_total:       int `json:",omitempty"`,
  condition_type:   string `json:",omitempty"`,
  condition_message: string `json:",omitempty"`,
  condition_data: string `json:",omitempty"`,
  condition_value_type: string `json:",omitempty"`,
  condition_restart_flags: u32 `json:",omitempty"`,
  trace_kind:       string `json:",omitempty"`,
  trace_id:         string `json:",omitempty"`,
  trace_depth:      int `json:",omitempty"`,
  trace_elapsed_ns: int `json:",omitempty"`,
  trace_delta_ns:   int `json:",omitempty"`,
  trace_values:     []string `json:",omitempty"`,
  checkpoint_bindings: int `json:",omitempty"`,
  checkpoints:      []Console_Checkpoint `json:",omitempty"`,
  runtime_live_allocations: int `json:",omitempty"`,
  runtime_live_bytes: int `json:",omitempty"`,
  runtime_total_allocations: int `json:",omitempty"`,
  runtime_total_allocated_bytes: int `json:",omitempty"`,
  runtime_total_frees: int `json:",omitempty"`,
  runtime_total_freed_bytes: int `json:",omitempty"`,
  managed_live_allocations: int `json:",omitempty"`,
  managed_live_bytes: int `json:",omitempty"`,
  managed_peak_bytes: int `json:",omitempty"`,
  managed_total_allocations: int `json:",omitempty"`,
  managed_total_allocated_bytes: int `json:",omitempty"`,
  managed_total_frees: int `json:",omitempty"`,
  managed_total_freed_bytes: int `json:",omitempty"`,
  physical_allocations: []Console_Physical_Allocation `json:",omitempty"`,
  physical_transfers: []Console_Physical_Transfer `json:",omitempty"`,
}

console_response_delete :: proc(response: ^Console_Response) {
  if response == nil {
    return
  }
  if response.id != "" do delete(response.id)
  if response.message != "" do delete(response.message)
  if response.output != "" do delete(response.output)
  if response.output_stream != "" do delete(response.output_stream)
  if response.pause_id != "" do delete(response.pause_id)
  for value in response.pause_values {
    delete(value)
  }
  delete(response.pause_values)
  for collection in response.pause_collections {
    delete(collection.path)
    delete(collection.shape)
    delete(collection.element_type)
    delete(collection.key_type)
    delete(collection.value_type)
  }
  delete(response.pause_collections)
  for collection in response.page_collections {
    delete(collection.path)
    delete(collection.shape)
    delete(collection.element_type)
    delete(collection.key_type)
    delete(collection.value_type)
  }
  delete(response.page_collections)
  for entry in response.page_entries {
    delete(entry.key)
    delete(entry.value)
  }
  delete(response.page_entries)
  delete(response.condition_type)
  delete(response.condition_message)
  delete(response.condition_data)
  delete(response.condition_value_type)
  delete(response.trace_kind)
  delete(response.trace_id)
  for value in response.trace_values {
    delete(value)
  }
  delete(response.trace_values)
  for allocation in response.physical_allocations {
    delete(allocation.owner_name)
    delete(allocation.retained_result_generations)
    for owner in allocation.retained_binding_owners {
      delete(owner.name)
    }
    delete(allocation.retained_binding_owners)
  }
  delete(response.physical_allocations)
  for transfer in response.physical_transfers {
    delete(transfer.owner_from_name)
    delete(transfer.owner_to_name)
  }
  delete(response.physical_transfers)
  for checkpoint in response.checkpoints {
    delete(checkpoint.name)
  }
  delete(response.checkpoints)
  for capability in response.capabilities {
    delete(capability.name)
    delete(capability.signature)
  }
  delete(response.capabilities)
  response^ = {}
}

console_request_delete :: proc(request: ^Console_Request) {
  if request == nil {
    return
  }
  if request.id != "" do delete(request.id)
  if request.op != "" do delete(request.op)
  if request.name != "" do delete(request.name)
  if request.signature != "" do delete(request.signature)
  if request.input != "" do delete(request.input)
  request^ = {}
}

Session :: struct {
  module_path:        string,
  state:              rawptr,
  state_size:         int,
  state_align:        int,
  core:               Core_Symbols,
  generation:         int,
  last_write:         time.Time,
  last_failed_write:  time.Time,
  has_reported_error: bool,
  retained:           [dynamic]dynlib.Library,
}

State_Size :: proc($T: typeid) -> int {
  return size_of(T)
}

State_Align :: proc($T: typeid) -> int {
  return align_of(T)
}

library_write_time :: proc(path: string) -> (time.Time, bool) {
  info, err := os.stat(path, context.temp_allocator)
  if err != nil {
    return {}, false
  }
  return info.modification_time, true
}

shadow_library_path :: proc(path: string, generation: int) -> string {
  dir, file := os.split_path(path)
  shadow_name := strings.clone(fmt.tprintf(".olive-reload-%d-%s", generation, file))
  defer delete(shadow_name)
  joined, err := os.join_path({dir, shadow_name}, context.allocator)
  if err != nil {
    return strings.clone(fmt.tprintf("%s.olive-reload-%d-%s", dir, generation, file))
  }
  return joined
}

copy_file :: proc(from, to: string) -> bool {
  data, read_err := os.read_entire_file_from_path(from, context.allocator)
  if read_err != nil {
    return false
  }
  defer delete(data)
  if os.exists(to) {
    _ = os.remove(to)
  }
  return os.write_entire_file(to, data) == nil
}

unload_core :: proc(core: ^Core_Symbols, state: rawptr) {
  if core.__handle != nil {
    if core.on_unload != nil && state != nil {
      core.on_unload(state)
    }
    _ = dynlib.unload_library(core.__handle)
    core^ = {}
  }
}

close_library :: proc(library: dynlib.Library) {
  if library != nil {
    _ = dynlib.unload_library(library)
  }
}

retain_app_symbol_library :: proc(session: ^Session, app_symbols: ^$T) {
  for field in reflect.struct_fields_zipped(T) {
    if field.name == "__handle" {
      field_ptr := rawptr(uintptr(app_symbols) + field.offset)
      handle := (^dynlib.Library)(field_ptr)^
        if handle != nil {
          append(&session.retained, handle)
          (^dynlib.Library)(field_ptr)^ = nil
        }
      return
    }
  }
}

release_retained_libraries :: proc(session: ^Session) {
  for library in session.retained {
    close_library(library)
  }
  delete(session.retained)
  session.retained = nil
}

cleanup_shadow_libraries :: proc(module_path: string) {
  dir, _ := os.split_path(module_path)
  entries, read_err := os.read_directory_by_path(dir, -1, context.temp_allocator)
  if read_err != nil {
    return
  }
  for entry in entries {
    if strings.contains(entry.name, ".olive-reload-") {
      path, join_err := os.join_path({dir, entry.name}, context.temp_allocator)
      if join_err == nil {
        _ = os.remove(path)
      }
    }
  }
}

unload_app_symbol_library :: proc(app_symbols: ^$T) {
  for field in reflect.struct_fields_zipped(T) {
    if field.name == "__handle" {
      field_ptr := rawptr(uintptr(app_symbols) + field.offset)
      handle := (^dynlib.Library)(field_ptr)^
        if handle != nil {
          close_library(handle)
          (^dynlib.Library)(field_ptr)^ = nil
        }
      return
    }
  }
}

load_core :: proc(path: string, state: rawptr, state_size, state_align: int, generation: int, is_reload: bool) -> (Core_Symbols, time.Time, string, bool) {
  shadow := shadow_library_path(path, generation)
  defer delete(shadow)
  if !copy_file(path, shadow) {
    return {}, {}, strings.clone("failed to copy reload library"), false
  }

  core := Core_Symbols{}
  _, ok := dynlib.initialize_symbols(&core, shadow)
  if !ok {
    return {}, {}, strings.clone("failed to load reload manifest"), false
  }

  if core.api_version == nil || core.state_size == nil || core.state_align == nil || core.on_load == nil || core.on_unload == nil {
    unload_core(&core, nil)
    return {}, {}, strings.clone("reload manifest is incomplete"), false
  }
  if core.api_version^ != MANIFEST_API_VERSION {
    unload_core(&core, nil)
    return {}, {}, strings.clone("reload API version mismatch"), false
  }
  layout_changed := core.state_size() != state_size || core.state_align() != state_align
  if layout_changed {
    unload_core(&core, nil)
    return {}, {}, strings.clone("reload state layout changed; stop and restart `olive run`. Any `olive watch` process can stay running."), false
  }

  write_time, time_ok := library_write_time(path)
  if !time_ok {
    unload_core(&core, nil)
    return {}, {}, strings.clone("failed to stat reload library"), false
  }
  core.on_load(state, is_reload)
  return core, write_time, "", true
}

start_session :: proc(module_path: string, app_symbols: ^$T, state: ^$S) -> (Session, string, bool) {
  state_size := size_of(S)
  state_align := align_of(S)
  core, write_time, message, ok := load_core(module_path, rawptr(state), state_size, state_align, 1, false)
  if !ok {
    return {}, message, false
  }
  shadow := shadow_library_path(module_path, 1)
  defer delete(shadow)
  _, symbols_ok := dynlib.initialize_symbols(app_symbols, shadow)
  if !symbols_ok {
    unload_core(&core, rawptr(state))
    return {}, strings.clone("failed to load app symbols"), false
  }
  return Session{
    module_path = module_path,
    state = rawptr(state),
    state_size = state_size,
    state_align = state_align,
    core = core,
    generation = 1,
    last_write = write_time,
    retained = make([dynamic]dynlib.Library),
  }, "", true
}

finish_session :: proc(session: ^Session) {
  unload_core(&session.core, session.state)
  release_retained_libraries(session)
  cleanup_shadow_libraries(session.module_path)
}

poll_session :: proc(session: ^Session, app_symbols: ^$T, state: ^$S, init_state: proc(^S) = nil) -> (Reload_Event, bool) {
  write_time, time_ok := library_write_time(session.module_path)
  if !time_ok {
    return {}, false
  }
  if time.time_to_unix_nano(write_time) == time.time_to_unix_nano(session.last_write) {
    return {}, false
  }
  failed_write_time := time.time_to_unix_nano(session.last_failed_write)
  current_write_time := time.time_to_unix_nano(write_time)
  if session.has_reported_error && current_write_time == failed_write_time {
    return {}, false
  }

  next_generation := session.generation + 1
  core, new_write_time, message, ok := load_core(session.module_path, session.state, session.state_size, session.state_align, next_generation, true)
  if !ok {
    session.last_failed_write = write_time
    session.has_reported_error = true
    return Reload_Event{kind = .Reload_Failed, generation = session.generation, message = message}, true
  }

  shadow := shadow_library_path(session.module_path, next_generation)
  defer delete(shadow)
  retain_app_symbol_library(session, app_symbols)
  _, symbols_ok := dynlib.initialize_symbols(app_symbols, shadow)
  if !symbols_ok {
    unload_core(&core, session.state)
    session.last_failed_write = write_time
    session.has_reported_error = true
    return Reload_Event{kind = .Reload_Failed, generation = session.generation, message = "failed to reload app symbols"}, true
  }

  if session.core.on_unload != nil {
    session.core.on_unload(session.state)
  }
  append(&session.retained, session.core.__handle)
  session.core = core
  session.generation = next_generation
  session.last_write = new_write_time
  session.has_reported_error = false
  return Reload_Event{kind = .Reloaded, generation = session.generation}, true
}

resource_name_ignored :: proc(name: string, ignore_names: []string) -> bool {
  for ignored in ignore_names {
    if name == ignored {
      return true
    }
  }
  return false
}

resource_write_time :: proc(path: string, ignore_names: []string = nil) -> (time.Time, string, bool) {
  info, stat_err := os.stat(path, context.temp_allocator)
  if stat_err != nil {
    return {}, "", false
  }
  if info.type == .Regular {
    if strings.has_suffix(info.name, ".odin") {
      return {}, "", false
    }
    return info.modification_time, strings.clone(path), true
  }
  if info.type != .Directory {
    return {}, "", false
  }

  newest := time.Time{}
  newest_path := ""
  found := false
  entries, read_err := os.read_directory_by_path(path, -1, context.temp_allocator)
  if read_err != nil {
    return {}, "", false
  }
  for entry in entries {
    if entry.name == "." || entry.name == ".." ||
      (entry.type == .Directory && resource_name_ignored(entry.name, ignore_names)) {
        continue
      }
    child := entry.fullpath
    if child == "" {
      joined, join_err := os.join_path({path, entry.name}, context.temp_allocator)
      if join_err != nil {
        continue
      }
      child = joined
    }
    child_time, child_path, child_found := resource_write_time(child, ignore_names)
    if child_found {
      if !found || time.time_to_unix_nano(child_time) > time.time_to_unix_nano(newest) {
        if found {
          delete(newest_path)
        }
        newest = child_time
        newest_path = child_path
        found = true
      } else {
        delete(child_path)
      }
    }
  }
  return newest, newest_path, found
}

newest_resource_write_time :: proc(paths: []string, ignore_names: []string = nil) -> (time.Time, string, bool) {
  newest := time.Time{}
  newest_path := ""
  found := false
  for path in paths {
    path_time, path_name, path_found := resource_write_time(path, ignore_names)
    if path_found {
      if !found || time.time_to_unix_nano(path_time) > time.time_to_unix_nano(newest) {
        if found {
          delete(newest_path)
        }
        newest = path_time
        newest_path = path_name
        found = true
      } else {
        delete(path_name)
      }
    }
  }
  return newest, newest_path, found
}

default_event_handler :: proc(event: Reload_Event) {
  switch event.kind {
  case .Started:
    fmt.printf("[olive] started generation=%d\n", event.generation)
  case .Reloaded:
    fmt.printf("[olive] reloaded generation=%d\n", event.generation)
  case .Restarted:
    fmt.printf("[olive] restarted generation=%d: %s\n", event.generation, event.message)
  case .Resource_Changed:
    fmt.printf("[olive] resource changed: %s\n", event.message)
  case .Reload_Failed:
    fmt.eprintf("[olive] reload failed: %s\n", event.message)
  }
}

event_kind_name :: proc(kind: Reload_Event_Kind) -> string {
  switch kind {
  case .Started:
    return "started"
  case .Reloaded:
    return "reloaded"
  case .Restarted:
    return "restarted"
  case .Resource_Changed:
    return "resource_changed"
  case .Reload_Failed:
    return "reload_failed"
  }
  return "unknown"
}

write_json_string :: proc(builder: ^strings.Builder, value: string) {
  strings.write_byte(builder, '"')
  for ch in transmute([]byte)value {
    switch ch {
    case '\\', '"':
      strings.write_byte(builder, '\\')
      strings.write_byte(builder, ch)
    case '\n':
      strings.write_string(builder, "\\n")
    case '\r':
      strings.write_string(builder, "\\r")
    case '\t':
      strings.write_string(builder, "\\t")
      case:
      strings.write_byte(builder, ch)
    }
  }
  strings.write_byte(builder, '"')
}

json_event_handler :: proc(event: Reload_Event) {
  b := strings.builder_make()
  defer strings.builder_destroy(&b)
  strings.write_string(&b, `OLIVE_RELOAD_EVENT	{`)
  strings.write_string(&b, `"kind":`)
  write_json_string(&b, event_kind_name(event.kind))
  fmt.sbprintf(&b, `,"generation":%d`, event.generation)
  strings.write_string(&b, `,"message":`)
  write_json_string(&b, event.message)
  strings.write_string(&b, "}\n")
  fmt.print(strings.to_string(b))
}

console_host_state :: proc(host: ^Run_Host) -> ^Console_Host_State {
  if host == nil || host.console == nil {
    return nil
  }
  return transmute(^Console_Host_State)host.console
}

console_enable :: proc(host: ^Run_Host, endpoint: string) -> bool {
  if host == nil || endpoint == "" {
    return false
  }
  state := console_host_state(host)
  cleanup_endpoint := state == nil
  if state == nil {
    state = new(Console_Host_State)
    state.allocator = context.allocator
    host.console = rawptr(state)
  } else {
    context.allocator = state.allocator
    cleanup_endpoint = state.endpoint != endpoint
    if state.endpoint != "" {
      delete(state.endpoint)
    }
  }
  state.endpoint = strings.clone(endpoint)
  state.host = host
  state.repl_worker.attached_pause_ctx = rawptr(state)
  state.repl_worker.attached_pause_handler = console_attached_pause
  state.repl_worker.attached_condition_ctx = rawptr(state)
  state.repl_worker.attached_condition_handler =
    console_attached_condition
  state.repl_worker.attached_trace_ctx = rawptr(state)
  state.repl_worker.attached_trace_handler =
    console_attached_trace
  state.repl_worker.attached_trace_values_ctx = rawptr(state)
  state.repl_worker.attached_trace_values_handler =
    console_attached_trace_values
  state.repl_worker.attached_output_ctx = rawptr(state)
  state.repl_worker.attached_output_handler =
    console_attached_output
  if !os.exists(state.endpoint) &&
     os.make_directory_all(state.endpoint) != nil {
    return false
  }
  if !os.is_dir(state.endpoint) {
    return false
  }
  if cleanup_endpoint {
    console_cleanup_endpoint(state.endpoint)
  }
  return true
}

console_clear_capabilities :: proc(host: ^Run_Host) {
  state := console_host_state(host)
  if state == nil {
    return
  }
  context.allocator = state.allocator
  for capability in state.capabilities {
    delete(capability.name)
    delete(capability.signature)
  }
  delete(state.capabilities)
  state.capabilities = nil
}

console_register_capability :: proc(
  host: ^Run_Host,
  name,
  signature: string,
  ctx: rawptr,
  handler: Console_Capability_Handler,
) -> bool {
  if host == nil || name == "" || signature == "" || handler == nil {
    return false
  }
  state := console_host_state(host)
  if state == nil {
    return false
  }
  context.allocator = state.allocator
  for &capability in state.capabilities {
    if capability.name == name {
      if capability.signature != signature {
        delete(capability.signature)
        capability.signature = strings.clone(signature)
      }
      capability.ctx = ctx
      capability.handler = handler
      return true
    }
  }
  append(&state.capabilities, Console_Capability{
    name = strings.clone(name),
    signature = strings.clone(signature),
    ctx = ctx,
    handler = handler,
  })
  return true
}

console_register_capability_raw :: proc(
  host: ^Run_Host,
  name,
  signature: string,
  ctx,
  handler: rawptr,
) -> bool {
  if handler == nil {
    return false
  }
  return console_register_capability(
    host,
    name,
    signature,
    ctx,
    transmute(Console_Capability_Handler)handler,
  )
}

console_host_delete :: proc(host: ^Run_Host) {
  if host == nil {
    return
  }
  state := console_host_state(host)
  if state == nil {
    return
  }
  context.allocator = state.allocator
  delete(state.endpoint)
  delete(state.active_request_id)
  delete(state.repl_pause_id)
  for value in state.repl_pause_values {
    delete(value)
  }
  delete(state.repl_pause_values)
  for collection in state.repl_pause_collection_views {
    delete(collection.path)
    delete(collection.shape)
    delete(collection.element_type)
    delete(collection.key_type)
    delete(collection.value_type)
  }
  delete(state.repl_pause_collection_views)
  kvist_repl.worker_attached_collections_delete(
    &state.repl_pause_collections,
  )
  for entry in state.repl_page_entries {
    delete(entry.key)
    delete(entry.value)
  }
  delete(state.repl_page_entries)
  delete(state.repl_condition_pause_id)
  delete(state.repl_condition_type)
  delete(state.repl_condition_message)
  delete(state.repl_condition_data)
  delete(state.repl_condition_value_type)
  delete(state.repl_restart_name)
  delete(state.repl_restart_value)
  for checkpoint in state.repl_checkpoint_views {
    delete(checkpoint.name)
  }
  delete(state.repl_checkpoint_views)
  for allocation in state.repl_physical_allocation_views {
    delete(allocation.owner_name)
    delete(allocation.retained_result_generations)
    for owner in allocation.retained_binding_owners {
      delete(owner.name)
    }
    delete(allocation.retained_binding_owners)
  }
  delete(state.repl_physical_allocation_views)
  for transfer in state.repl_physical_transfer_views {
    delete(transfer.owner_from_name)
    delete(transfer.owner_to_name)
  }
  delete(state.repl_physical_transfer_views)
  delete(state.repl_checkpoint_message)
  console_clear_capabilities(host)
  kvist_repl.worker_delete(&state.repl_worker)
  free(state)
  host.console = nil
}

console_append_collection_views :: proc(
  state: ^Console_Host_State,
  start: int,
) {
  if state == nil {
    return
  }
  context.allocator = state.allocator
  for collection, descriptor in
    state.repl_pause_collections.collections[start:] {
    append(&state.repl_pause_collection_views, Console_Debug_Collection{
      path = strings.clone(string(
        collection.path.data[:collection.path.length],
      )),
      shape = strings.clone(string(
        collection.shape.data[:collection.shape.length],
      )),
      element_type = strings.clone(string(
        collection.element_type.data[:collection.element_type.length],
      )),
      key_type = strings.clone(string(
        collection.key_type.data[:collection.key_type.length],
      )),
      value_type = strings.clone(string(
        collection.value_type.data[:collection.value_type.length],
      )),
      descriptor = start+descriptor,
    })
  }
}

console_file_path :: proc(endpoint, prefix, id, suffix: string) -> (string, bool) {
  if !console_request_id_valid(id) {
    return "", false
  }
  file := fmt.aprintf("%s%s%s", prefix, id, suffix)
  defer delete(file)
  path, err := os.join_path({endpoint, file}, context.allocator)
  return path, err == nil
}

console_request_id_valid :: proc(id: string) -> bool {
  if len(id) == 0 || len(id) > CONSOLE_REQUEST_ID_LIMIT {
    return false
  }
  for ch in id {
    if (ch >= 'a' && ch <= 'z') ||
       (ch >= 'A' && ch <= 'Z') ||
       (ch >= '0' && ch <= '9') ||
       ch == '-' ||
       ch == '_' ||
       ch == '.' {
      continue
    }
    return false
  }
  return true
}

console_mailbox_file_id :: proc(name: string) -> (string, bool) {
  prefixes := [?]string{"request-", "response-", ".request-", ".response-"}
  suffixes := [?]string{".json", ".json", ".tmp", ".tmp"}
  for prefix, index in prefixes {
    suffix := suffixes[index]
    if !strings.has_prefix(name, prefix) ||
       !strings.has_suffix(name, suffix) ||
       len(name) <= len(prefix)+len(suffix) {
      continue
    }
    id := name[len(prefix):len(name)-len(suffix)]
    return id, true
  }
  return "", false
}

console_cleanup_endpoint :: proc(endpoint: string) {
  entries, read_err :=
    os.read_directory_by_path(
      endpoint,
      -1,
      context.temp_allocator,
    )
  if read_err != nil {
    return
  }
  for entry in entries {
    if _, owned := console_mailbox_file_id(entry.name); !owned {
      continue
    }
    path, join_err :=
      os.join_path({endpoint, entry.name}, context.allocator)
    if join_err != nil {
      continue
    }
    _ = os.remove(path)
    delete(path)
  }
}

console_receive :: proc(
  endpoint,
  request_id: string,
  timeout := CONSOLE_REQUEST_TIMEOUT,
) -> (response: Console_Response, message: string, ok: bool) {
  if !console_request_id_valid(request_id) {
    return response, strings.clone("invalid attached console request id"), false
  }
  response_path, response_path_ok :=
    console_file_path(endpoint, "response-", request_id, ".json")
  if !response_path_ok {
    return response, strings.clone("failed to create console response path"), false
  }
  defer delete(response_path)
  started := time.tick_now()
  for time.tick_since(started) < timeout {
    if os.exists(response_path) {
      data, read_err :=
        os.read_entire_file_from_path(response_path, context.allocator)
      if read_err == nil {
        decode_err := json.unmarshal(data, &response)
        delete(data)
        _ = os.remove(response_path)
        if decode_err == nil &&
           response.id == request_id &&
           response.protocol_version == CONSOLE_PROTOCOL_VERSION {
          return response, "", true
        }
        return response,
               strings.clone("invalid attached console response"),
               false
      }
    }
    time.sleep(10 * time.Millisecond)
  }
  return response,
         strings.clone("timed out waiting for application checkpoint"),
         false
}

console_submit :: proc(
  endpoint: string,
  request: Console_Request,
  timeout := CONSOLE_REQUEST_TIMEOUT,
) -> (response: Console_Response, message: string, ok: bool) {
  if endpoint == "" ||
     !console_request_id_valid(request.id) ||
     request.op == "" ||
     request.protocol_version != CONSOLE_PROTOCOL_VERSION {
    return response,
           strings.clone("invalid attached console request"),
           false
  }
  request_path, request_path_ok :=
    console_file_path(endpoint, "request-", request.id, ".json")
  if !request_path_ok {
    return response, strings.clone("failed to create console request path"), false
  }
  defer delete(request_path)
  temp_path, temp_path_ok :=
    console_file_path(endpoint, ".request-", request.id, ".tmp")
  if !temp_path_ok {
    return response, strings.clone("failed to create console temporary path"), false
  }
  defer delete(temp_path)
  response_path, response_path_ok :=
    console_file_path(endpoint, "response-", request.id, ".json")
  if !response_path_ok {
    return response, strings.clone("failed to create console response path"), false
  }
  defer delete(response_path)
  if os.exists(request_path) ||
     os.exists(temp_path) ||
     os.exists(response_path) {
    return response,
           strings.clone("attached console request id is already in use"),
           false
  }
  bytes, marshal_err := json.marshal(request)
  if marshal_err != nil ||
     len(bytes) > CONSOLE_REQUEST_BYTES_LIMIT ||
     os.write_entire_file(temp_path, bytes) != nil ||
     os.rename(temp_path, request_path) != nil {
    delete(bytes)
    _ = os.remove(temp_path)
    return response, strings.clone("failed to publish console request"), false
  }
  delete(bytes)
  response, message, ok =
    console_receive(endpoint, request.id, timeout)
  if ok {
    return response, message, ok
  }
  _ = os.remove(request_path)
  return response, message, false
}

console_write_response :: proc(
  host: ^Run_Host,
  request: Console_Request,
  response: Console_Response,
) -> bool {
  state := console_host_state(host)
  if state == nil {
    return false
  }
  path, path_ok :=
    console_file_path(state.endpoint, "response-", request.id, ".json")
  if !path_ok {
    return false
  }
  defer delete(path)
  temp_path, temp_ok :=
    console_file_path(state.endpoint, ".response-", request.id, ".tmp")
  if !temp_ok {
    return false
  }
  defer delete(temp_path)
  if os.exists(path) || os.exists(temp_path) {
    return false
  }
  bytes, marshal_err := json.marshal(response)
  if marshal_err != nil {
    return false
  }
  defer delete(bytes)
  if os.write_entire_file(temp_path, bytes) != nil {
    _ = os.remove(temp_path)
    return false
  }
  renamed := os.rename(temp_path, path) == nil
  if !renamed {
    _ = os.remove(temp_path)
  }
  return renamed
}

console_attached_condition :: proc(
  ctx: rawptr,
  pause_id,
  condition_type,
  message,
  data,
  value_type: string,
  restart_flags: u32,
) {
  context = runtime.default_context()
  state := transmute(^Console_Host_State)ctx
  if state == nil {
    return
  }
  context.allocator = state.allocator
  delete(state.repl_condition_pause_id)
  delete(state.repl_condition_type)
  delete(state.repl_condition_message)
  delete(state.repl_condition_data)
  delete(state.repl_condition_value_type)
  delete(state.repl_restart_name)
  delete(state.repl_restart_value)
  state.repl_condition_pause_id = strings.clone(pause_id)
  state.repl_condition_type = strings.clone(condition_type)
  state.repl_condition_message = strings.clone(message)
  state.repl_condition_data = strings.clone(data)
  state.repl_condition_value_type = strings.clone(value_type)
  state.repl_condition_restart_flags = restart_flags
  state.repl_restart_name = ""
  state.repl_restart_value = ""
}

console_attached_trace :: proc(
  ctx: rawptr,
  kind,
  trace_id: string,
  depth,
  elapsed_ns,
  delta_ns: int,
) {
  context = runtime.default_context()
  state := transmute(^Console_Host_State)ctx
  if state == nil ||
     state.host == nil ||
     state.active_request_id == "" {
    return
  }
  context.allocator = state.allocator
  session := (^Session)(state.host.session)
  generation := 0
  if session != nil {
    generation = session.generation
  }
  request := Console_Request{id = state.active_request_id}
  response := Console_Response{
    protocol_version = CONSOLE_PROTOCOL_VERSION,
    id = state.active_request_id,
    success = true,
    generation = generation,
    repl_generation = len(state.repl_worker.generations),
    trace_kind = kind,
    trace_id = trace_id,
    trace_depth = depth,
    trace_elapsed_ns = elapsed_ns,
    trace_delta_ns = delta_ns,
  }
  if !console_write_response(state.host, request, response) {
    return
  }
  response_path, path_ok :=
    console_file_path(
      state.endpoint,
      "response-",
      state.active_request_id,
      ".json",
    )
  if !path_ok {
    return
  }
  defer delete(response_path)
  started := time.tick_now()
  for os.exists(response_path) &&
      time.tick_since(started) < CONSOLE_REQUEST_TIMEOUT {
    time.sleep(5 * time.Millisecond)
  }
}

console_attached_output :: proc(
  ctx: rawptr,
  stream,
  text: string,
) {
  context = runtime.default_context()
  state := transmute(^Console_Host_State)ctx
  if state == nil ||
     state.host == nil ||
     state.active_request_id == "" {
    return
  }
  context.allocator = state.allocator
  session := (^Session)(state.host.session)
  generation := 0
  if session != nil {
    generation = session.generation
  }
  request := Console_Request{id = state.active_request_id}
  response := Console_Response{
    protocol_version = CONSOLE_PROTOCOL_VERSION,
    id = state.active_request_id,
    success = true,
    generation = generation,
    repl_generation = len(state.repl_worker.generations),
    output = text,
    output_stream = stream,
  }
  if !console_write_response(state.host, request, response) {
    return
  }
  response_path, path_ok :=
    console_file_path(
      state.endpoint,
      "response-",
      state.active_request_id,
      ".json",
    )
  if !path_ok {
    return
  }
  defer delete(response_path)
  started := time.tick_now()
  for os.exists(response_path) &&
      time.tick_since(started) < CONSOLE_REQUEST_TIMEOUT {
    time.sleep(5 * time.Millisecond)
  }
}

console_attached_trace_values :: proc(
  ctx: rawptr,
  trace_id: string,
  values: [^]kvist_repl.Rendered_Value,
  value_count: int,
) {
  context = runtime.default_context()
  state := transmute(^Console_Host_State)ctx
  if state == nil ||
     state.host == nil ||
     state.active_request_id == "" {
    return
  }
  context.allocator = state.allocator
  rendered: [dynamic]string
  defer delete(rendered)
  for value in values[:value_count] {
    append(&rendered, string(value.data[:value.length]))
  }
  session := (^Session)(state.host.session)
  generation := 0
  if session != nil {
    generation = session.generation
  }
  request := Console_Request{id = state.active_request_id}
  response := Console_Response{
    protocol_version = CONSOLE_PROTOCOL_VERSION,
    id = state.active_request_id,
    success = true,
    generation = generation,
    repl_generation = len(state.repl_worker.generations),
    trace_kind = "trace-values",
    trace_id = trace_id,
    trace_values = rendered[:],
  }
  if !console_write_response(state.host, request, response) {
    return
  }
  response_path, path_ok :=
    console_file_path(
      state.endpoint,
      "response-",
      state.active_request_id,
      ".json",
    )
  if !path_ok {
    return
  }
  defer delete(response_path)
  started := time.tick_now()
  for os.exists(response_path) &&
      time.tick_since(started) < CONSOLE_REQUEST_TIMEOUT {
    time.sleep(5 * time.Millisecond)
  }
}

console_attached_pause :: proc(
  ctx: rawptr,
  pause_id: string,
  values: [^]kvist_repl.Rendered_Value,
  value_count: int,
  collections: [^]kvist_repl.Debug_Collection,
  collection_count: int,
  restart_selection: ^kvist_repl.Restart_Selection,
) {
  context = runtime.default_context()
  state := transmute(^Console_Host_State)ctx
  if state == nil ||
     state.host == nil ||
     state.active_request_id == "" {
    return
  }
  context.allocator = state.allocator
  delete(state.repl_pause_id)
  state.repl_pause_id = strings.clone(pause_id)
  for value in state.repl_pause_values {
    delete(value)
  }
  clear(&state.repl_pause_values)
  for value in values[:value_count] {
    append(
      &state.repl_pause_values,
      strings.clone(string(value.data[:value.length])),
    )
  }
  for collection in state.repl_pause_collection_views {
    delete(collection.path)
    delete(collection.shape)
    delete(collection.element_type)
    delete(collection.key_type)
    delete(collection.value_type)
  }
  clear(&state.repl_pause_collection_views)
  kvist_repl.worker_attached_collections_begin(
    &state.repl_pause_collections,
    collections[:collection_count],
    state.allocator,
  )
  console_append_collection_views(state, 0)
  state.repl_paused = true
  session := (^Session)(state.host.session)
  generation := 0
  if session != nil {
    generation = session.generation
  }
  request := Console_Request{id = state.active_request_id}
  response := Console_Response{
    protocol_version = CONSOLE_PROTOCOL_VERSION,
    id = state.active_request_id,
    success = true,
    generation = generation,
    repl_generation = len(state.repl_worker.generations),
    paused = true,
    pause_id = pause_id,
    pause_values = state.repl_pause_values[:],
    pause_collections =
      state.repl_pause_collection_views[:],
  }
  if state.repl_condition_pause_id == pause_id {
    response.condition_type = state.repl_condition_type
    response.condition_message = state.repl_condition_message
    response.condition_data = state.repl_condition_data
    response.condition_value_type =
      state.repl_condition_value_type
    response.condition_restart_flags =
      state.repl_condition_restart_flags
  }
  if !console_write_response(state.host, request, response) {
    state.repl_paused = false
    delete(state.repl_pause_id)
    state.repl_pause_id = ""
    for value in state.repl_pause_values {
      delete(value)
    }
    clear(&state.repl_pause_values)
    kvist_repl.worker_attached_collections_delete(
      &state.repl_pause_collections,
    )
    for collection in state.repl_pause_collection_views {
      delete(collection.path)
      delete(collection.shape)
      delete(collection.element_type)
      delete(collection.key_type)
      delete(collection.value_type)
    }
    clear(&state.repl_pause_collection_views)
    return
  }
  for state.repl_paused {
    _ = console_poll(state.host)
    if state.repl_paused {
      time.sleep(5 * time.Millisecond)
    }
  }
  if restart_selection != nil &&
     state.repl_restart_name != "" {
    restart_selection.name = kvist_repl.Rendered_Value{
      data = raw_data(state.repl_restart_name),
      length = len(state.repl_restart_name),
    }
    restart_selection.value = kvist_repl.Rendered_Value{
      data = raw_data(state.repl_restart_value),
      length = len(state.repl_restart_value),
    }
  }
  delete(state.repl_pause_id)
  state.repl_pause_id = ""
  for value in state.repl_pause_values {
    delete(value)
  }
  clear(&state.repl_pause_values)
  kvist_repl.worker_attached_collections_delete(
    &state.repl_pause_collections,
  )
  for collection in state.repl_pause_collection_views {
    delete(collection.path)
    delete(collection.shape)
    delete(collection.element_type)
    delete(collection.key_type)
    delete(collection.value_type)
  }
  clear(&state.repl_pause_collection_views)
}

console_handle_request :: proc(
  host: ^Run_Host,
  request: Console_Request,
) -> Console_Response {
  session := (^Session)(host.session)
  generation := 0
  if session != nil {
    generation = session.generation
  }
  response := Console_Response{
    protocol_version = CONSOLE_PROTOCOL_VERSION,
    id = request.id,
    generation = generation,
  }
  console := console_host_state(host)
  if console == nil {
    response.message = "attached console is not enabled"
    return response
  }
  context.allocator = console.allocator
  if request.protocol_version != CONSOLE_PROTOCOL_VERSION {
    response.message = "attached console protocol version mismatch"
    return response
  }
  if console.repl_paused &&
     request.op != "debug-continue" &&
     request.op != "debug-step" &&
     request.op != "debug-step-over" &&
     request.op != "debug-step-out" &&
     request.op != "debug-abort" &&
     request.op != "debug-page" &&
     request.op != "debug-restart" &&
     request.op != "handshake" &&
     request.op != "capabilities" &&
     request.op != "status" {
    response.message =
      "attached REPL is paused; use a debug control request or status"
    response.paused = true
    response.pause_id = console.repl_pause_id
    response.pause_values = console.repl_pause_values[:]
    response.pause_collections =
      console.repl_pause_collection_views[:]
    response.repl_generation = len(console.repl_worker.generations)
    return response
  }
  switch request.op {
  case "handshake", "capabilities", "status":
    response.success = true
    response.capabilities = console.capabilities[:]
    response.repl_generation = len(console.repl_worker.generations)
    response.paused = console.repl_paused
    response.pause_id = console.repl_pause_id
    response.pause_values = console.repl_pause_values[:]
    response.pause_collections =
      console.repl_pause_collection_views[:]
  case "load-generation":
    if request.input == "" {
      response.message = "attached generation path is required"
      return response
    }
    delete(console.active_request_id)
    console.active_request_id = strings.clone(request.id)
    message, loaded :=
      kvist_repl.worker_load_and_run(
        &console.repl_worker,
        request.input,
      )
    delete(console.active_request_id)
    console.active_request_id = ""
    response.success = loaded
    response.message = message
    response.aborted = console.repl_worker.last_run_aborted
    response.output =
      kvist_repl.worker_take_output(&console.repl_worker)
    response.repl_generation = len(console.repl_worker.generations)
  case "checkpoint", "checkpoint-restore", "checkpoint-drop":
    if request.name == "" {
      response.message = "checkpoint name must not be empty"
      return response
    }
    count := 0
    operation_ok := false
    operation_message := ""
    switch request.op {
    case "checkpoint":
      count, operation_message, operation_ok =
        kvist_repl.worker_checkpoint_capture(
          &console.repl_worker,
          request.name,
        )
    case "checkpoint-restore":
      count, operation_message, operation_ok =
        kvist_repl.worker_checkpoint_restore(
          &console.repl_worker,
          request.name,
        )
    case "checkpoint-drop":
      operation_message, operation_ok =
        kvist_repl.worker_checkpoint_drop(
          &console.repl_worker,
          request.name,
        )
    }
    delete(console.repl_checkpoint_message)
    console.repl_checkpoint_message = operation_message
    response.message = console.repl_checkpoint_message
    response.success = operation_ok
    response.checkpoint_bindings = count
    response.repl_generation = len(console.repl_worker.generations)
  case "checkpoints":
    for checkpoint in console.repl_checkpoint_views {
      delete(checkpoint.name)
    }
    clear(&console.repl_checkpoint_views)
    checkpoint_count :=
      kvist_repl.worker_checkpoint_inventory_count(
        &console.repl_worker,
      )
    for checkpoint_index in 0..<checkpoint_count {
      name, bindings, found :=
        kvist_repl.worker_checkpoint_inventory_entry(
          &console.repl_worker,
          checkpoint_index,
        )
      if found {
        append(
          &console.repl_checkpoint_views,
          Console_Checkpoint{
            name = strings.clone(name),
            bindings = bindings,
          },
        )
      }
    }
    response.success = true
    response.checkpoints = console.repl_checkpoint_views[:]
    response.repl_generation = len(console.repl_worker.generations)
  case "runtime-allocations":
    stats :=
      kvist_repl.worker_allocation_stats(
        &console.repl_worker,
      )
    response.success = true
    response.repl_generation =
      len(console.repl_worker.generations)
    response.runtime_live_allocations =
      stats.live_allocations
    response.runtime_live_bytes =
      stats.live_bytes
    response.runtime_total_allocations =
      stats.total_allocations
    response.runtime_total_allocated_bytes =
      stats.total_allocated_bytes
    response.runtime_total_frees =
      stats.total_frees
    response.runtime_total_freed_bytes =
      stats.total_freed_bytes
    response.managed_live_allocations =
      stats.managed_live_allocations
    response.managed_live_bytes =
      stats.managed_live_bytes
    response.managed_peak_bytes =
      stats.managed_peak_bytes
    response.managed_total_allocations =
      stats.managed_total_allocations
    response.managed_total_allocated_bytes =
      stats.managed_total_allocated_bytes
    response.managed_total_frees =
      stats.managed_total_frees
    response.managed_total_freed_bytes =
      stats.managed_total_freed_bytes
  case "physical-allocations":
    for allocation in console.repl_physical_allocation_views {
      delete(allocation.owner_name)
      delete(allocation.retained_result_generations)
      for owner in allocation.retained_binding_owners {
        delete(owner.name)
      }
      delete(allocation.retained_binding_owners)
    }
    for transfer in console.repl_physical_transfer_views {
      delete(transfer.owner_from_name)
      delete(transfer.owner_to_name)
    }
    clear(&console.repl_physical_allocation_views)
    clear(&console.repl_physical_transfer_views)
    inventory :=
      kvist_repl.worker_managed_allocation_inventory(
        &console.repl_worker,
        console.allocator,
      )
    for allocation in inventory {
      retained_result_generations := make(
        [dynamic]int,
        0,
        len(allocation.retained_result_generations),
        console.allocator,
      )
      append(
        &retained_result_generations,
        ..allocation.retained_result_generations[:],
      )
      retained_binding_owners := make(
        [dynamic]kvist_repl.Worker_Managed_Binding_Owner,
        0,
        len(allocation.retained_binding_owners),
        console.allocator,
      )
      for owner in allocation.retained_binding_owners {
        append(
          &retained_binding_owners,
          kvist_repl.Worker_Managed_Binding_Owner{
            name = strings.clone(owner.name),
            generation = owner.generation,
          },
        )
      }
      append(
        &console.repl_physical_allocation_views,
        Console_Physical_Allocation{
          allocation_id = allocation.allocation,
          size = allocation.size,
          alignment = allocation.alignment,
          generation = allocation.generation,
          owner_kind = allocation.owner_kind,
          owner_generation = allocation.owner_generation,
          owner_name = strings.clone(allocation.owner_name),
          retained_result_generations =
            retained_result_generations,
          retained_binding_owners =
            retained_binding_owners,
        },
      )
    }
    delete(inventory)
    response.physical_allocations =
      console.repl_physical_allocation_views[:]
    transfers :=
      kvist_repl.worker_managed_transfer_history(
        &console.repl_worker,
        console.allocator,
      )
    for transfer in transfers {
      append(
        &console.repl_physical_transfer_views,
        Console_Physical_Transfer{
          sequence = transfer.sequence,
          allocation_id = transfer.allocation,
          generation = transfer.generation,
          owner_from_kind = transfer.owner_from_kind,
          owner_from_generation =
            transfer.owner_from_generation,
          owner_from_name =
            strings.clone(transfer.owner_from_name),
          owner_to_kind = transfer.owner_to_kind,
          owner_to_generation =
            transfer.owner_to_generation,
          owner_to_name =
            strings.clone(transfer.owner_to_name),
          action = transfer.action,
        },
      )
    }
    delete(transfers)
    response.physical_transfers =
      console.repl_physical_transfer_views[:]
    response.success = true
    response.repl_generation =
      len(console.repl_worker.generations)
  case "trace-next":
    fields := strings.split(
      request.input,
      "\t",
      context.temp_allocator,
    )
    if len(fields) != 2 {
      response.message = "invalid attached trace request"
      return response
    }
    trace_limit, trace_limit_ok := strconv.parse_int(fields[0])
    trace_value_limit, trace_value_limit_ok :=
      strconv.parse_int(fields[1])
    if !trace_limit_ok || !trace_value_limit_ok ||
       trace_limit <= 0 ||
       trace_value_limit < 0 {
      response.message = "invalid attached trace bounds"
      return response
    }
    kvist_repl.worker_trace_next(
      &console.repl_worker,
      trace_limit,
      trace_value_limit,
    )
    response.success = true
    response.repl_generation = len(console.repl_worker.generations)
  case "debug-continue", "debug-step", "debug-step-over", "debug-step-out", "debug-abort":
    if !console.repl_paused {
      response.message = "attached REPL is not paused"
      return response
    }
    if request.input != "" &&
       request.input != console.repl_pause_id {
      response.message = "attached pause id does not match"
      return response
    }
    if request.op == "debug-abort" {
      console.repl_worker.abort_requested = true
      console.repl_worker.abort_unwind_depth =
        console.repl_worker.frame_depth
      console.repl_worker.step_armed = false
    } else if request.op != "debug-continue" {
      console.repl_worker.step_armed = true
      console.repl_worker.step_depth =
        console.repl_worker.frame_depth
      switch request.op {
      case "debug-step-over":
        console.repl_worker.step_mode = .Over
      case "debug-step-out":
        console.repl_worker.step_mode = .Out
      case:
        console.repl_worker.step_mode = .Into
      }
    }
    console.repl_paused = false
    response.success = true
    response.repl_generation = len(console.repl_worker.generations)
  case "debug-page":
    fields := strings.split(
      request.input,
      "\t",
      context.temp_allocator,
    )
    if len(fields) != 3 {
      response.message = "invalid attached debug page request"
      return response
    }
    descriptor, descriptor_ok := strconv.parse_int(fields[0])
    offset, offset_ok := strconv.parse_int(fields[1])
    limit, limit_ok := strconv.parse_int(fields[2])
    if !descriptor_ok || !offset_ok || !limit_ok ||
       descriptor < 0 ||
       descriptor >= len(
         console.repl_pause_collections.collections,
       ) ||
       offset < 0 || limit <= 0 || limit > 100 {
      response.message = "invalid attached debug page bounds"
      return response
    }
    entries, total, discovered_at, rendered :=
      kvist_repl.worker_render_attached_page(
        &console.repl_pause_collections,
        descriptor,
        offset,
        limit,
      )
    context.allocator = console.allocator
    if !rendered {
      kvist_repl.attached_page_entries_delete(
        entries[:],
        console.allocator,
      )
      response.message = "attached debug page capture failed"
      return response
    }
    for entry in console.repl_page_entries {
      delete(entry.key)
      delete(entry.value)
    }
    clear(&console.repl_page_entries)
    for entry in entries {
      append(&console.repl_page_entries, Console_Page_Entry{
        index = entry.index,
        key = strings.clone(entry.key),
        value = strings.clone(entry.value),
      })
    }
    kvist_repl.attached_page_entries_delete(
      entries[:],
      console.allocator,
    )
    discovered_view_start :=
      len(console.repl_pause_collection_views)
    console_append_collection_views(
      console,
      discovered_at,
    )
    response.success = true
    response.repl_generation = len(console.repl_worker.generations)
    response.pause_id = console.repl_pause_id
    response.page_entries = console.repl_page_entries[:]
    response.page_total = total
    response.page_collections =
      console.repl_pause_collection_views[
        discovered_view_start:
      ]
  case "debug-restart":
    if !console.repl_paused ||
       request.name == "" {
      response.message = "attached REPL has no active restart"
      return response
    }
    delete(console.repl_restart_name)
    delete(console.repl_restart_value)
    if request.name == "continue" {
      console.repl_restart_name = ""
    } else {
      console.repl_restart_name =
        strings.clone(request.name)
    }
    console.repl_restart_value =
      strings.clone(request.input)
    console.repl_paused = false
    response.success = true
    response.repl_generation =
      len(console.repl_worker.generations)
  case "reset-session":
    kvist_repl.worker_delete(&console.repl_worker)
    delete(console.repl_checkpoint_message)
    console.repl_checkpoint_message = ""
    for checkpoint in console.repl_checkpoint_views {
      delete(checkpoint.name)
    }
    clear(&console.repl_checkpoint_views)
    delete(console.repl_condition_pause_id)
    delete(console.repl_condition_type)
    delete(console.repl_condition_message)
    delete(console.repl_condition_data)
    delete(console.repl_condition_value_type)
    delete(console.repl_restart_name)
    delete(console.repl_restart_value)
    console.repl_condition_pause_id = ""
    console.repl_condition_type = ""
    console.repl_condition_message = ""
    console.repl_condition_data = ""
    console.repl_condition_value_type = ""
    console.repl_condition_restart_flags = 0
    console.repl_restart_name = ""
    console.repl_restart_value = ""
    console.repl_worker.attached_pause_ctx = rawptr(console)
    console.repl_worker.attached_pause_handler =
      console_attached_pause
    console.repl_worker.attached_condition_ctx = rawptr(console)
    console.repl_worker.attached_condition_handler =
      console_attached_condition
    console.repl_worker.attached_trace_ctx = rawptr(console)
    console.repl_worker.attached_trace_handler =
      console_attached_trace
    console.repl_worker.attached_trace_values_ctx = rawptr(console)
    console.repl_worker.attached_trace_values_handler =
      console_attached_trace_values
    console.repl_worker.attached_output_ctx = rawptr(console)
    console.repl_worker.attached_output_handler =
      console_attached_output
    response.success = true
    response.repl_generation = 0
  case "invoke":
    for capability in console.capabilities {
      if capability.name != request.name {
        continue
      }
      if request.signature != "" &&
         request.signature != capability.signature {
        response.message =
          fmt.tprintf(
            "capability %q ABI mismatch: host exposes %s",
            request.name,
            capability.signature,
          )
        return response
      }
      output, message, invoked :=
        capability.handler(capability.ctx, request.input)
      response.success = invoked
      response.output = output
      response.message = message
      return response
    }
    response.message = fmt.tprintf("unknown capability %q", request.name)
  case "reload":
    host.console_reload_requested = true
    response.success = true
    response.reload_requested = true
  case:
    response.message = fmt.tprintf(
      "unsupported attached console operation %q",
      request.op,
    )
  }
  return response
}

console_poll :: proc(host: ^Run_Host) -> int {
  console := console_host_state(host)
  if console == nil || console.endpoint == "" {
    return 0
  }
  entries, read_err :=
    os.read_directory_by_path(
      console.endpoint,
      -1,
      context.temp_allocator,
    )
  if read_err != nil {
    return 0
  }
  handled := 0
  for entry in entries {
    if !strings.has_prefix(entry.name, "request-") ||
       !strings.has_suffix(entry.name, ".json") {
      continue
    }
    file_request_id :=
      entry.name[
        len("request-"):
        len(entry.name)-len(".json")
      ]
    if !console_request_id_valid(file_request_id) {
      request_path, join_err :=
        os.join_path(
          {console.endpoint, entry.name},
          context.allocator,
        )
      if join_err == nil {
        _ = os.remove(request_path)
        delete(request_path)
      }
      continue
    }
    if console.active_request_id != "" &&
       entry.name ==
         fmt.tprintf(
           "request-%s.json",
           console.active_request_id,
         ) {
      continue
    }
    request_path, join_err :=
      os.join_path(
        {console.endpoint, entry.name},
        context.allocator,
      )
    if join_err != nil {
      continue
    }
    data, read_request_err :=
      os.read_entire_file_from_path(request_path, context.allocator)
    if read_request_err != nil {
      delete(request_path)
      continue
    }
    if len(data) > CONSOLE_REQUEST_BYTES_LIMIT {
      delete(data)
      _ = os.remove(request_path)
      delete(request_path)
      continue
    }
    request := Console_Request{}
    unmarshal_err := json.unmarshal(data, &request)
    delete(data)
    if unmarshal_err == nil &&
       request.protocol_version == CONSOLE_PROTOCOL_VERSION &&
       request.id == file_request_id &&
       request.op != "" {
      response := console_handle_request(host, request)
      _ = console_write_response(host, request, response)
      handled += 1
    }
    console_request_delete(&request)
    _ = os.remove(request_path)
    delete(request_path)
  }
  return handled
}

request_exit :: proc(host: ^Run_Host) {
  host.exit_requested = true
}

clear_checkpoint_error :: proc(host: ^Run_Host) {
  if host.checkpoint_error != "" {
    delete(host.checkpoint_error)
    host.checkpoint_error = ""
  }
}

checkpoint :: proc(host: ^Run_Host) -> bool {
  if host == nil || host.session == nil {
    return false
  }
  session := (^Session)(host.session)
  _ = console_poll(host)
  if host.console_reload_requested {
    return true
  }
  write_time, time_ok := library_write_time(session.module_path)
  if !time_ok {
    clear_checkpoint_error(host)
    host.checkpoint_error = strings.clone("failed to stat reload library")
    return true
  }

  current_write_time := time.time_to_unix_nano(write_time)
  if current_write_time == time.time_to_unix_nano(session.last_write) {
    return false
  }
  if session.has_reported_error && current_write_time == time.time_to_unix_nano(session.last_failed_write) {
    return false
  }
  return true
}

run_host :: proc(
  module_path: string,
  app_symbols: ^$T,
  state: ^$S,
  run: proc(^T, ^S, ^Run_Host),
  on_event := default_event_handler,
 ) -> int {
  force_reload: proc(^T, ^S) -> bool
  force_restart: proc(^T, ^S) -> bool
  init_state: proc(^S)
  return run_host_with_options(module_path, app_symbols, state, run, on_event, force_reload, force_restart, init_state)
}

run_host_with_options :: proc(
  module_path: string,
  app_symbols: ^$T,
  state: ^$S,
  run: proc(^T, ^S, ^Run_Host),
  on_event := default_event_handler,
  force_reload: proc(^T, ^S) -> bool,
  force_restart: proc(^T, ^S) -> bool,
  init_state: proc(^S),
) -> int {
  on_resource_change: proc(^T, ^S, string)
  return run_host_with_resources(
    module_path,
    app_symbols,
    state,
    run,
    on_event,
    force_reload,
    force_restart,
    init_state,
    nil,
    on_resource_change,
  )
}

run_host_with_resources :: proc(
  module_path: string,
  app_symbols: ^$T,
  state: ^$S,
  run: proc(^T, ^S, ^Run_Host),
  on_event := default_event_handler,
  force_reload: proc(^T, ^S) -> bool,
  force_restart: proc(^T, ^S) -> bool,
  init_state: proc(^S),
  resource_paths: []string,
  on_resource_change: proc(^T, ^S, string),
  resource_debounce := 150 * time.Millisecond,
) -> int {
  return run_host_with_resources_and_ignores(
    module_path,
    app_symbols,
    state,
    run,
    on_event,
    force_reload,
    force_restart,
    init_state,
    resource_paths,
    on_resource_change,
    []string{".git", ".olive"},
    resource_debounce,
  )
}

run_host_with_resources_and_ignores :: proc(
  module_path: string,
  app_symbols: ^$T,
  state: ^$S,
  run: proc(^T, ^S, ^Run_Host),
  on_event := default_event_handler,
  force_reload: proc(^T, ^S) -> bool,
  force_restart: proc(^T, ^S) -> bool,
  init_state: proc(^S),
  resource_paths: []string,
  on_resource_change: proc(^T, ^S, string),
  resource_ignore_names: []string,
  resource_debounce := 150 * time.Millisecond,
) -> int {
  session, message, ok := start_session(module_path, app_symbols, state)
  if !ok {
    on_event(Reload_Event{kind = .Reload_Failed, message = message})
    return 1
  }
  defer finish_session(&session)
  defer unload_app_symbol_library(app_symbols)
  on_event(Reload_Event{kind = .Started, generation = session.generation})

  host := Run_Host{session = rawptr(&session)}
  console_endpoint, console_enabled :=
    os.lookup_env(CONSOLE_ENDPOINT_ENV, context.allocator)
  if console_enabled && console_endpoint != "" {
    if !console_enable(&host, console_endpoint) {
      on_event(Reload_Event{
        kind = .Reload_Failed,
        generation = session.generation,
        message = "failed to create attached REPL endpoint",
      })
      console_host_delete(&host)
      return 1
    }
    delete(console_endpoint)
  } else if console_endpoint != "" {
    delete(console_endpoint)
  }
  defer console_host_delete(&host)
  last_resource_write := time.Time{}
  if len(resource_paths) > 0 && on_resource_change != nil {
    initial_resource_write, initial_resource_path, initial_resource_found := newest_resource_write_time(resource_paths, resource_ignore_names)
    if initial_resource_found {
      last_resource_write = initial_resource_write
      delete(initial_resource_path)
    }
  }
  for {
    host.exit_requested = false
    clear_checkpoint_error(&host)
    // Registrations describe the current app generation. Never leave a
    // removed capability pointing into an older retained library.
    console_clear_capabilities(&host)
    run(app_symbols, state, &host)
    if host.checkpoint_error != "" {
      on_event(Reload_Event{kind = .Reload_Failed, generation = session.generation, message = host.checkpoint_error})
      return 1
    }
    if host.exit_requested {
      return 0
    }
    if force_restart != nil && force_restart(app_symbols, state) && init_state != nil {
      if session.core.on_unload != nil {
        session.core.on_unload(session.state)
      }
      init_state(state)
      session.core.on_load(session.state, false)
      on_event(Reload_Event{kind = .Restarted, generation = session.generation, message = "app requested restart"})
    }
    force :=
      (force_reload != nil && force_reload(app_symbols, state)) ||
      host.console_reload_requested
    host.console_reload_requested = false
    if force {
      session.last_write = {}
    }
    event, changed := poll_session(&session, app_symbols, state, init_state)
    if changed {
      on_event(event)
    }
    if len(resource_paths) > 0 && on_resource_change != nil {
      resource_write, resource_path, resource_found := newest_resource_write_time(resource_paths, resource_ignore_names)
      if resource_found {
        changed_resource := time.time_to_unix_nano(resource_write) != time.time_to_unix_nano(last_resource_write)
        if changed_resource {
          delete(resource_path)
          time.sleep(resource_debounce)
          resource_write, resource_path, resource_found = newest_resource_write_time(resource_paths, resource_ignore_names)
          if resource_found {
            last_resource_write = resource_write
            on_resource_change(app_symbols, state, resource_path)
            on_event(Reload_Event{kind = .Resource_Changed, generation = session.generation, message = resource_path})
          }
        }
        if resource_path != "" {
          delete(resource_path)
        }
      }
    }
  }
  return 0
}
