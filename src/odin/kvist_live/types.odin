// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist_live

import kvist "../kvist"

Value_Kind :: enum {
    Nil,
    Bool,
    Int,
    String,
    Keyword,
    Handle,
}

Value :: struct {
    kind:       Value_Kind,
    bool_value: bool,
    int_value:  i64,
    text:       string,
}

Runtime_Error :: struct {
    message: string,
}

State_Entry :: struct {
    key:   string,
    value: Value,
}

Runtime_Event_Kind :: enum {
    Capability_Registered,
    Command_Registered,
    Hook_Registered,
    Module_Loaded,
    Module_Reloaded,
    Module_Shutdown,
    Capability_Called,
    Command_Called,
    Hook_Emitted,
    Error,
}

Runtime_Event :: struct {
    kind:        Runtime_Event_Kind,
    module_name: string,
    detail:      string,
}

Capability_Handler :: #type proc(runtime: ^Runtime, capability_name: string, args: []Value) -> (Value, Runtime_Error, bool)
Command_Handler :: #type proc(runtime: ^Runtime, module: ^Live_Module, command: ^Live_Command, args: []Value) -> (Value, Runtime_Error, bool)
Hook_Handler :: #type proc(runtime: ^Runtime, module: ^Live_Module, hook: ^Live_Hook, payload: []Value) -> (Runtime_Error, bool)
Module_Init_Hook :: #type proc(runtime: ^Runtime, module: ^Live_Module) -> (Runtime_Error, bool)
Module_Shutdown_Hook :: #type proc(runtime: ^Runtime, module: ^Live_Module)
Module_Migrate_Hook :: #type proc(runtime: ^Runtime, old_module: Live_Module, new_module: ^Live_Module) -> (Runtime_Error, bool)

Host_Capability :: struct {
    name:    string,
    doc:     string,
    handler: Capability_Handler,
}

Behavior_Definition :: struct {
    name: string,
    doc:  string,
    params: [dynamic]string,
    body: [dynamic]kvist.CST_Form,
}

Live_Command :: struct {
    name:              string,
    module_name:       string,
    module_generation: int,
    doc:               string,
    body:              [dynamic]kvist.CST_Form,
    handler:           Command_Handler,
}

Live_Hook :: struct {
    name:              string,
    module_name:       string,
    module_generation: int,
    doc:               string,
    body:              [dynamic]kvist.CST_Form,
    handler:           Hook_Handler,
}

Module_Definition :: struct {
    name:          string,
    version:       string,
    initial_state: [dynamic]State_Entry,
    functions:     [dynamic]Behavior_Definition,
    commands:      [dynamic]Behavior_Definition,
    hooks:         [dynamic]Behavior_Definition,
    init:          Module_Init_Hook,
    shutdown:      Module_Shutdown_Hook,
    migrate:       Module_Migrate_Hook,
}

Module_Load_Config :: struct {
    init:     Module_Init_Hook,
    shutdown: Module_Shutdown_Hook,
    migrate:  Module_Migrate_Hook,
}

Module_Reloader :: struct {
    module_path:     string,
    watch_dir:       string,
    last_signature:  string,
    has_loaded:      bool,
}

Live_Module :: struct {
    runtime:         ^Runtime,
    name:           string,
    version:        string,
    state:          [dynamic]State_Entry,
    reload_from_version: string,
    reload_state:   [dynamic]State_Entry,
    functions:      [dynamic]Behavior_Definition,
    commands:       [dynamic]Behavior_Definition,
    hooks:          [dynamic]Behavior_Definition,
    init:           Module_Init_Hook,
    shutdown:       Module_Shutdown_Hook,
    migrate:        Module_Migrate_Hook,
    generation:     int,
    init_count:     int,
    reload_count:   int,
    last_error:     string,
}

Runtime_Config :: struct {
    app_name:     string,
    live_enabled: bool,
}

Runtime :: struct {
    config:         Runtime_Config,
    capabilities:   [dynamic]Host_Capability,
    commands:       [dynamic]Live_Command,
    hooks:          [dynamic]Live_Hook,
    modules:        [dynamic]Live_Module,
    events:         [dynamic]Runtime_Event,
    next_generation: int,
}
