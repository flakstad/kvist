package olive_reload

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strings"
import "core:time"

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
    force := force_reload != nil && force_reload(app_symbols, state)
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
