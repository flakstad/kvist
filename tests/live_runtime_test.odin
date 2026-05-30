package tests

import "core:testing"
import kvist_live "../src/kvist_live"

last_capability_name: string
last_capability_arg_count: int
shutdown_count: int

echo_capability :: proc(runtime: ^kvist_live.Runtime, capability_name: string, args: []kvist_live.Value) -> (kvist_live.Value, kvist_live.Runtime_Error, bool) {
    last_capability_name = capability_name
    last_capability_arg_count = len(args)
    return kvist_live.value_string("ok"), kvist_live.Runtime_Error{}, true
}

module_init_default_mode :: proc(runtime: ^kvist_live.Runtime, module: ^kvist_live.Live_Module) -> (kvist_live.Runtime_Error, bool) {
    if _, ok := kvist_live.module_state_get_string(module, "mode"); !ok {
        kvist_live.module_state_put_string(module, "mode", "default")
    }
    return kvist_live.Runtime_Error{}, true
}

module_shutdown_counter :: proc(runtime: ^kvist_live.Runtime, module: ^kvist_live.Live_Module) {
    shutdown_count += 1
}

first_loaded_module :: proc(runtime: ^kvist_live.Runtime) -> (^kvist_live.Live_Module, bool) {
    if len(runtime.modules) == 0 {
        return nil, false
    }
    return &runtime.modules[0], true
}

stateful_count_capability :: proc(runtime: ^kvist_live.Runtime, capability_name: string, args: []kvist_live.Value) -> (kvist_live.Value, kvist_live.Runtime_Error, bool) {
    module, ok := first_loaded_module(runtime)
    if !ok {
        return kvist_live.value_nil(), kvist_live.Runtime_Error{message = "no loaded module"}, false
    }

    count := i64(0)
    if entry, found := kvist_live.module_state_get(module, "cap-count"); found && entry.value.kind == .Int {
        count = entry.value.int_value
    }
    count += 1

    next := kvist_live.value_int(count)
    defer kvist_live.value_delete(&next)
    kvist_live.module_state_put(module, "cap-count", next)
    return kvist_live.value_int(count), kvist_live.Runtime_Error{}, true
}

stateful_hook_counter_capability :: proc(runtime: ^kvist_live.Runtime, capability_name: string, args: []kvist_live.Value) -> (kvist_live.Value, kvist_live.Runtime_Error, bool) {
    module, ok := first_loaded_module(runtime)
    if !ok {
        return kvist_live.value_nil(), kvist_live.Runtime_Error{message = "no loaded module"}, false
    }

    count := i64(0)
    if entry, found := kvist_live.module_state_get(module, "hook-count"); found && entry.value.kind == .Int {
        count = entry.value.int_value
    }
    count += 1

    next := kvist_live.value_int(count)
    defer kvist_live.value_delete(&next)
    kvist_live.module_state_put(module, "hook-count", next)
    return kvist_live.value_nil(), kvist_live.Runtime_Error{}, true
}

module_migrate_copy_mode :: proc(runtime: ^kvist_live.Runtime, old_module: kvist_live.Live_Module, new_module: ^kvist_live.Live_Module) -> (kvist_live.Runtime_Error, bool) {
    old_mode, ok := kvist_live.state_entries_get_string(old_module.state[:], "mode")
    if ok {
        kvist_live.module_state_put_string(new_module, "mode", old_mode)
    }
    if count_entry, found := kvist_live.state_entries_get(old_module.state[:], "cap-count"); found {
        kvist_live.module_state_put(new_module, "cap-count", count_entry.value)
    }
    if hook_entry, found := kvist_live.state_entries_get(old_module.state[:], "hook-count"); found {
        kvist_live.module_state_put(new_module, "hook-count", hook_entry.value)
    }
    kvist_live.module_state_put_string(new_module, "migrated-from", old_module.version)
    return kvist_live.Runtime_Error{}, true
}

must_parse_module :: proc(t: ^testing.T, source: string) -> kvist_live.Module_Definition {
    def, err, ok := kvist_live.module_definition_from_kvist_source(source)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, err.message, "")
    return def
}

@(test)
live_runtime_registers_and_calls_capabilities :: proc(t: ^testing.T) {
    runtime := kvist_live.new_runtime(kvist_live.Runtime_Config{
        app_name = "tests",
        live_enabled = true,
    })
    defer kvist_live.runtime_delete(&runtime)

    err, ok := kvist_live.register_capability(&runtime, kvist_live.Host_Capability{
        name = "echo",
        doc = "Return a simple confirmation.",
        handler = echo_capability,
    })
    testing.expect_value(t, ok, true)
    testing.expect_value(t, err.message, "")

    arg := kvist_live.value_int(42)
    defer kvist_live.value_delete(&arg)

    result, call_err, call_ok := kvist_live.call_capability(&runtime, "echo", []kvist_live.Value{arg})
    defer kvist_live.value_delete(&result)

    testing.expect_value(t, call_ok, true)
    testing.expect_value(t, call_err.message, "")
    testing.expect_value(t, last_capability_name, "echo")
    testing.expect_value(t, last_capability_arg_count, 1)
    testing.expect_value(t, result.kind, kvist_live.Value_Kind.String)
    testing.expect_value(t, result.text, "ok")
    testing.expect_value(t, len(runtime.events) >= 2, true)
}

@(test)
live_loader_reads_real_kvist_source :: proc(t: ^testing.T) {
    source := `(live/module {:name "commands" :version "v2"})
(defn run-hook []
  (host/call "tests.mark-hook"))
(defvar greeting "hello")
(live/command tick {:message "hello" :counter-key "run-count"}
  greeting
  (run-hook)
  (hook/emit "after-command"))
(live/hook after-command {:hook-message "done"}
  (run-hook))
(defvar retries 3)
(defvar enabled true)`

    def, err, ok := kvist_live.module_definition_from_kvist_source(source)
    defer kvist_live.state_entry_slice_delete(&def.initial_state)
    defer kvist_live.delete_behavior_definition_slice(&def.functions)
    defer kvist_live.delete_behavior_definition_slice(&def.commands)
    defer kvist_live.delete_behavior_definition_slice(&def.hooks)
    defer {
        if def.name != "" {
            delete(def.name)
        }
        if def.version != "" {
            delete(def.version)
        }
    }

    testing.expect_value(t, ok, true)
    testing.expect_value(t, err.message, "")
    testing.expect_value(t, def.name, "commands")
    testing.expect_value(t, def.version, "v2")

    message_entry, message_ok := kvist_live.state_entries_get(def.initial_state[:], "message")
    testing.expect_value(t, message_ok, true)
    testing.expect_value(t, message_entry.value.kind, kvist_live.Value_Kind.String)
    testing.expect_value(t, message_entry.value.text, "hello")

    command_name_entry, command_name_ok := kvist_live.state_entries_get(def.initial_state[:], "command-name")
    testing.expect_value(t, command_name_ok, true)
    testing.expect_value(t, command_name_entry.value.text, "tick")

    hook_name_entry, hook_name_ok := kvist_live.state_entries_get(def.initial_state[:], "hook-name")
    testing.expect_value(t, hook_name_ok, true)
    testing.expect_value(t, hook_name_entry.value.text, "after-command")

    testing.expect_value(t, len(def.functions), 1)
    testing.expect_value(t, def.functions[0].name, "run-hook")
    testing.expect_value(t, len(def.functions[0].params), 0)
    testing.expect_value(t, len(def.functions[0].body) > 0, true)
    testing.expect_value(t, len(def.commands), 1)
    testing.expect_value(t, def.commands[0].name, "tick")
    testing.expect_value(t, len(def.commands[0].body) > 0, true)
    testing.expect_value(t, len(def.hooks), 1)
    testing.expect_value(t, def.hooks[0].name, "after-command")

    retry_entry, retry_ok := kvist_live.state_entries_get(def.initial_state[:], "retries")
    testing.expect_value(t, retry_ok, true)
    testing.expect_value(t, retry_entry.value.kind, kvist_live.Value_Kind.Int)
    testing.expect_value(t, retry_entry.value.int_value, i64(3))
    greeting_entry, greeting_ok := kvist_live.state_entries_get(def.initial_state[:], "greeting")
    testing.expect_value(t, greeting_ok, true)
    testing.expect_value(t, greeting_entry.value.text, "hello")
}

@(test)
live_runtime_reloads_modules_with_migration :: proc(t: ^testing.T) {
    shutdown_count = 0

    runtime := kvist_live.new_runtime(kvist_live.Runtime_Config{
        app_name = "tests",
        live_enabled = true,
    })
    defer kvist_live.runtime_delete(&runtime)

    capability_err, capability_ok := kvist_live.register_capability(&runtime, kvist_live.Host_Capability{
        name = "tests.next-count",
        doc = "Increment and return the command count.",
        handler = stateful_count_capability,
    })
    testing.expect_value(t, capability_ok, true)
    testing.expect_value(t, capability_err.message, "")

    hook_cap_err, hook_cap_ok := kvist_live.register_capability(&runtime, kvist_live.Host_Capability{
        name = "tests.mark-hook",
        doc = "Increment the hook count.",
        handler = stateful_hook_counter_capability,
    })
    testing.expect_value(t, hook_cap_ok, true)
    testing.expect_value(t, hook_cap_err.message, "")

    initial_def := must_parse_module(t, `(live/module {:name "commands" :version "v1"})
(defn mark-and-count []
  (let [count (host/call "tests.next-count")]
    (state/set! "count" count)
    count))
(defn notify-hook []
  (host/call "tests.mark-hook"))
(live/command tick {:counter-key "count"}
  (let [count (mark-and-count)]
    (hook/emit "after-run")
    count))
(live/hook after-run {:doc "Test hook."}
  (notify-hook))`)
    defer {
        kvist_live.state_entry_slice_delete(&initial_def.initial_state)
        kvist_live.delete_behavior_definition_slice(&initial_def.functions)
        kvist_live.delete_behavior_definition_slice(&initial_def.commands)
        kvist_live.delete_behavior_definition_slice(&initial_def.hooks)
        if initial_def.name != "" {
            delete(initial_def.name)
        }
        if initial_def.version != "" {
            delete(initial_def.version)
        }
    }
    initial_def.init = module_init_default_mode
    initial_def.shutdown = module_shutdown_counter

    load_err, load_ok := kvist_live.load_module(&runtime, initial_def)
    testing.expect_value(t, load_ok, true)
    testing.expect_value(t, load_err.message, "")

    command_result, command_err, command_ok := kvist_live.invoke_command(&runtime, "tick", nil)
    defer kvist_live.value_delete(&command_result)
    testing.expect_value(t, command_ok, true)
    testing.expect_value(t, command_err.message, "")
    testing.expect_value(t, command_result.int_value, i64(1))

    module, found := kvist_live.loaded_module(&runtime, "commands")
    testing.expect_value(t, found, true)
    mode, mode_ok := kvist_live.module_state_get_string(module, "mode")
    testing.expect_value(t, mode_ok, true)
    testing.expect_value(t, mode, "default")
    cap_count_entry, cap_count_ok := kvist_live.module_state_get(module, "cap-count")
    testing.expect_value(t, cap_count_ok, true)
    testing.expect_value(t, cap_count_entry.value.int_value, i64(1))
    hook_count_entry, hook_count_ok := kvist_live.module_state_get(module, "hook-count")
    testing.expect_value(t, hook_count_ok, true)
    testing.expect_value(t, hook_count_entry.value.int_value, i64(1))

    kvist_live.module_state_put_string(module, "mode", "patched")

    next_def := must_parse_module(t, `(live/module {:name "commands" :version "v2"})
(defn mark-and-count []
  (let [count (host/call "tests.next-count")]
    (state/set! "count" count)
    count))
(defn notify-hook []
  (host/call "tests.mark-hook"))
(live/command tick {:counter-key "count"}
  (let [count (mark-and-count)]
    (hook/emit "after-run")
    count))
(live/hook after-run {:doc "Test hook."}
  (notify-hook))`)
    defer {
        kvist_live.state_entry_slice_delete(&next_def.initial_state)
        kvist_live.delete_behavior_definition_slice(&next_def.functions)
        kvist_live.delete_behavior_definition_slice(&next_def.commands)
        kvist_live.delete_behavior_definition_slice(&next_def.hooks)
        if next_def.name != "" {
            delete(next_def.name)
        }
        if next_def.version != "" {
            delete(next_def.version)
        }
    }
    next_def.init = module_init_default_mode
    next_def.shutdown = module_shutdown_counter
    next_def.migrate = module_migrate_copy_mode

    reload_err, reload_ok := kvist_live.reload_module(&runtime, next_def)
    testing.expect_value(t, reload_ok, true)
    testing.expect_value(t, reload_err.message, "")
    testing.expect_value(t, shutdown_count, 1)

    reloaded, reload_found := kvist_live.loaded_module(&runtime, "commands")
    testing.expect_value(t, reload_found, true)
    testing.expect_value(t, reloaded.version, "v2")
    testing.expect_value(t, reloaded.reload_count, 1)
    testing.expect_value(t, reloaded.init_count, 2)

    carried_mode, carried_mode_ok := kvist_live.module_state_get_string(reloaded, "mode")
    testing.expect_value(t, carried_mode_ok, true)
    testing.expect_value(t, carried_mode, "patched")

    migrated_from, migrated_from_ok := kvist_live.module_state_get_string(reloaded, "migrated-from")
    testing.expect_value(t, migrated_from_ok, true)
    testing.expect_value(t, migrated_from, "v1")

    reloaded_result, reloaded_err, reloaded_ok := kvist_live.invoke_command(&runtime, "tick", nil)
    defer kvist_live.value_delete(&reloaded_result)
    testing.expect_value(t, reloaded_ok, true)
    testing.expect_value(t, reloaded_err.message, "")
    testing.expect_value(t, reloaded_result.int_value, i64(2))
    cap_count_entry_2, cap_count_ok_2 := kvist_live.module_state_get(reloaded, "cap-count")
    testing.expect_value(t, cap_count_ok_2, true)
    testing.expect_value(t, cap_count_entry_2.value.int_value, i64(2))
    hook_count_entry_2, hook_count_ok_2 := kvist_live.module_state_get(reloaded, "hook-count")
    testing.expect_value(t, hook_count_ok_2, true)
    testing.expect_value(t, hook_count_entry_2.value.int_value, i64(2))
}

@(test)
live_runtime_executes_reusable_live_functions :: proc(t: ^testing.T) {
    runtime := kvist_live.new_runtime(kvist_live.Runtime_Config{
        app_name = "tests",
        live_enabled = true,
    })
    defer kvist_live.runtime_delete(&runtime)

    capability_err, capability_ok := kvist_live.register_capability(&runtime, kvist_live.Host_Capability{
        name = "tests.next-count",
        doc = "Increment and return the command count.",
        handler = stateful_count_capability,
    })
    testing.expect_value(t, capability_ok, true)
    testing.expect_value(t, capability_err.message, "")

    def := must_parse_module(t, `(live/module {:name "math" :version "v1"})
(defn add-and-bump [delta]
  (+ (host/call "tests.next-count") delta))
(live/command tick {}
  (add-and-bump 4))`)
    defer {
        kvist_live.state_entry_slice_delete(&def.initial_state)
        kvist_live.delete_behavior_definition_slice(&def.functions)
        kvist_live.delete_behavior_definition_slice(&def.commands)
        kvist_live.delete_behavior_definition_slice(&def.hooks)
        if def.name != "" {
            delete(def.name)
        }
        if def.version != "" {
            delete(def.version)
        }
    }

    load_err, load_ok := kvist_live.load_module(&runtime, def)
    testing.expect_value(t, load_ok, true)
    testing.expect_value(t, load_err.message, "")

    result, invoke_err, invoke_ok := kvist_live.invoke_command(&runtime, "tick", nil)
    defer kvist_live.value_delete(&result)
    testing.expect_value(t, invoke_ok, true)
    testing.expect_value(t, invoke_err.message, "")
    testing.expect_value(t, result.kind, kvist_live.Value_Kind.Int)
    testing.expect_value(t, result.int_value, i64(5))
}

@(test)
live_runtime_resolves_module_bindings_as_symbols :: proc(t: ^testing.T) {
    runtime := kvist_live.new_runtime(kvist_live.Runtime_Config{
        app_name = "tests",
        live_enabled = true,
    })
    defer kvist_live.runtime_delete(&runtime)

    def := must_parse_module(t, `(live/module {:name "bindings" :version "v1"})
(def message "hello")
(defconst bonus 2)
(defn suffix [] " world")
(live/command tick {}
  (str message (suffix) " +" bonus))`)
    defer {
        kvist_live.state_entry_slice_delete(&def.initial_state)
        kvist_live.delete_behavior_definition_slice(&def.functions)
        kvist_live.delete_behavior_definition_slice(&def.commands)
        kvist_live.delete_behavior_definition_slice(&def.hooks)
        if def.name != "" {
            delete(def.name)
        }
        if def.version != "" {
            delete(def.version)
        }
    }

    load_err, load_ok := kvist_live.load_module(&runtime, def)
    testing.expect_value(t, load_ok, true)
    testing.expect_value(t, load_err.message, "")

    result, invoke_err, invoke_ok := kvist_live.invoke_command(&runtime, "tick", nil)
    defer kvist_live.value_delete(&result)
    testing.expect_value(t, invoke_ok, true)
    testing.expect_value(t, invoke_err.message, "")
    testing.expect_value(t, result.kind, kvist_live.Value_Kind.String)
    testing.expect_value(t, result.text, "hello world +2")
}

@(test)
live_runtime_uses_same_named_defn_for_entrypoints :: proc(t: ^testing.T) {
    runtime := kvist_live.new_runtime(kvist_live.Runtime_Config{
        app_name = "tests",
        live_enabled = true,
    })
    defer kvist_live.runtime_delete(&runtime)

    capability_err, capability_ok := kvist_live.register_capability(&runtime, kvist_live.Host_Capability{
        name = "tests.mark-hook",
        doc = "Increment hook count.",
        handler = stateful_hook_counter_capability,
    })
    testing.expect_value(t, capability_ok, true)
    testing.expect_value(t, capability_err.message, "")

    def := must_parse_module(t, `(live/module {:name "entrypoints" :version "v1"})
(def greeting "hello")
(defn tick []
  (str greeting " from tick"))
(defn after-command []
  (host/call "tests.mark-hook"))
(live/command tick)
(live/hook after-command)`)
    defer {
        kvist_live.state_entry_slice_delete(&def.initial_state)
        kvist_live.delete_behavior_definition_slice(&def.functions)
        kvist_live.delete_behavior_definition_slice(&def.commands)
        kvist_live.delete_behavior_definition_slice(&def.hooks)
        if def.name != "" {
            delete(def.name)
        }
        if def.version != "" {
            delete(def.version)
        }
    }

    load_err, load_ok := kvist_live.load_module(&runtime, def)
    testing.expect_value(t, load_ok, true)
    testing.expect_value(t, load_err.message, "")

    result, invoke_err, invoke_ok := kvist_live.invoke_command(&runtime, "tick", nil)
    defer kvist_live.value_delete(&result)
    testing.expect_value(t, invoke_ok, true)
    testing.expect_value(t, invoke_err.message, "")
    testing.expect_value(t, result.kind, kvist_live.Value_Kind.String)
    testing.expect_value(t, result.text, "hello from tick")

    hook_err, hook_ok := kvist_live.emit_hook(&runtime, "after-command", nil)
    testing.expect_value(t, hook_ok, true)
    testing.expect_value(t, hook_err.message, "")

    module, module_ok := kvist_live.loaded_module(&runtime, "entrypoints")
    testing.expect_value(t, module_ok, true)
    hook_count, hook_count_ok := kvist_live.module_state_get(module, "hook-count")
    testing.expect_value(t, hook_count_ok, true)
    testing.expect_value(t, hook_count.value.int_value, i64(1))
}

@(test)
live_runtime_accepts_bodyless_entrypoints_with_options_omitted :: proc(t: ^testing.T) {
    def, err, ok := kvist_live.module_definition_from_kvist_source(`(live/module {:name "demo" :version "v1"})
(defn tick [] "ok")
(live/command tick)
(defn after-command [] nil)
(live/hook after-command)`)
    defer kvist_live.state_entry_slice_delete(&def.initial_state)
    defer kvist_live.delete_behavior_definition_slice(&def.functions)
    defer kvist_live.delete_behavior_definition_slice(&def.commands)
    defer kvist_live.delete_behavior_definition_slice(&def.hooks)
    defer {
        if def.name != "" {
            delete(def.name)
        }
        if def.version != "" {
            delete(def.version)
        }
    }

    testing.expect_value(t, ok, true)
    testing.expect_value(t, err.message, "")
    testing.expect_value(t, len(def.commands), 1)
    testing.expect_value(t, len(def.commands[0].body) > 0, true)
    testing.expect_value(t, len(def.hooks), 1)
    testing.expect_value(t, len(def.hooks[0].body) > 0, true)
}

@(test)
live_runtime_evaluates_cond_clauses :: proc(t: ^testing.T) {
    runtime := kvist_live.new_runtime(kvist_live.Runtime_Config{
        app_name = "tests",
        live_enabled = true,
    })
    defer kvist_live.runtime_delete(&runtime)

    def := must_parse_module(t, `(live/module {:name "cond-demo" :version "v1"})
(def level 3)
(defn tick []
  (cond
    [(= level 1) "one"]
    [(= level 2) "two"]
    [(= level 3) "three"]
    [:else "other"]))
(live/command tick)`)
    defer {
        kvist_live.state_entry_slice_delete(&def.initial_state)
        kvist_live.delete_behavior_definition_slice(&def.functions)
        kvist_live.delete_behavior_definition_slice(&def.commands)
        kvist_live.delete_behavior_definition_slice(&def.hooks)
        if def.name != "" {
            delete(def.name)
        }
        if def.version != "" {
            delete(def.version)
        }
    }

    load_err, load_ok := kvist_live.load_module(&runtime, def)
    testing.expect_value(t, load_ok, true)
    testing.expect_value(t, load_err.message, "")

    result, invoke_err, invoke_ok := kvist_live.invoke_command(&runtime, "tick", nil)
    defer kvist_live.value_delete(&result)
    testing.expect_value(t, invoke_ok, true)
    testing.expect_value(t, invoke_err.message, "")
    testing.expect_value(t, result.kind, kvist_live.Value_Kind.String)
    testing.expect_value(t, result.text, "three")
}

@(test)
live_runtime_runs_source_defined_lifecycle_functions :: proc(t: ^testing.T) {
    runtime := kvist_live.new_runtime(kvist_live.Runtime_Config{
        app_name = "tests",
        live_enabled = true,
    })
    defer kvist_live.runtime_delete(&runtime)

    capability_err, capability_ok := kvist_live.register_capability(&runtime, kvist_live.Host_Capability{
        name = "tests.mark-hook",
        doc = "Increment hook count.",
        handler = stateful_hook_counter_capability,
    })
    testing.expect_value(t, capability_ok, true)
    testing.expect_value(t, capability_err.message, "")

    def := must_parse_module(t, `(live/module {:name "lifecycle" :version "v1"})
(def init-message "booted")
(def shutdown-message "stopped")
(defn init []
  (state/set! "init-message-seen" init-message))
(defn shutdown []
  (host/call "tests.mark-hook")
  (state/set! "shutdown-message-seen" shutdown-message))
(defn tick [] "ok")
(live/command tick)`)
    defer {
        kvist_live.state_entry_slice_delete(&def.initial_state)
        kvist_live.delete_behavior_definition_slice(&def.functions)
        kvist_live.delete_behavior_definition_slice(&def.commands)
        kvist_live.delete_behavior_definition_slice(&def.hooks)
        if def.name != "" {
            delete(def.name)
        }
        if def.version != "" {
            delete(def.version)
        }
    }

    load_err, load_ok := kvist_live.load_module(&runtime, def)
    testing.expect_value(t, load_ok, true)
    testing.expect_value(t, load_err.message, "")

    module, module_ok := kvist_live.loaded_module(&runtime, "lifecycle")
    testing.expect_value(t, module_ok, true)
    init_seen, init_seen_ok := kvist_live.module_state_get_string(module, "init-message-seen")
    testing.expect_value(t, init_seen_ok, true)
    testing.expect_value(t, init_seen, "booted")

    next_def := must_parse_module(t, `(live/module {:name "lifecycle" :version "v2"})
(def init-message "rebooted")
(def shutdown-message "stopped")
(defn init []
  (state/set! "init-message-seen" init-message))
(defn shutdown []
  (host/call "tests.mark-hook")
  (state/set! "shutdown-message-seen" shutdown-message))
(defn tick [] "ok")
(live/command tick)`)
    defer {
        kvist_live.state_entry_slice_delete(&next_def.initial_state)
        kvist_live.delete_behavior_definition_slice(&next_def.functions)
        kvist_live.delete_behavior_definition_slice(&next_def.commands)
        kvist_live.delete_behavior_definition_slice(&next_def.hooks)
        if next_def.name != "" {
            delete(next_def.name)
        }
        if next_def.version != "" {
            delete(next_def.version)
        }
    }

    reload_err, reload_ok := kvist_live.reload_module(&runtime, next_def)
    testing.expect_value(t, reload_ok, true)
    testing.expect_value(t, reload_err.message, "")

    reloaded, reloaded_ok := kvist_live.loaded_module(&runtime, "lifecycle")
    testing.expect_value(t, reloaded_ok, true)
    init_seen_2, init_seen_ok_2 := kvist_live.module_state_get_string(reloaded, "init-message-seen")
    testing.expect_value(t, init_seen_ok_2, true)
    testing.expect_value(t, init_seen_2, "rebooted")

    saw_hook_capability := false
    for event in runtime.events {
        if event.kind == .Capability_Called && event.module_name == "tests.mark-hook" {
            saw_hook_capability = true
        }
    }
    testing.expect_value(t, saw_hook_capability, true)
}
