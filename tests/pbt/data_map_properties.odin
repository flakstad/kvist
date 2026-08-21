// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

DATA_MAP_KEY_COUNT :: 4

Data_Map_State :: struct {
	present: [DATA_MAP_KEY_COUNT]bool,
	values:  [DATA_MAP_KEY_COUNT]int,
}

Data_Map_Command_Kind :: enum {
	Assoc,
	Dissoc,
	Lookup,
}

Data_Map_Command :: struct {
	kind:  Data_Map_Command_Kind,
	key:   int,
	value: int,
}

Data_Map_Observation :: struct {
	success:   bool,
	present:   [DATA_MAP_KEY_COUNT]bool,
	values:    [DATA_MAP_KEY_COUNT]int,
	canonical: string,
	raw:       string,
	error:     string,
}

data_map_commands_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	model := pbt.State_Model(Data_Map_State, Data_Map_Command, Data_Map_Observation) {
		initial = data_map_initial,
		command = data_map_command,
		run = data_map_run,
		next_state = data_map_next_state,
		postcondition = data_map_postcondition,
		invariant = data_map_invariant,
		command_name = data_map_command_name,
		state_detail = data_map_state_detail,
		value_detail = data_map_value_detail,
	}
	return pbt.run_commands(t, model, {
		min_len = 1,
		max_len = 8,
		skip_success_events = true,
	})
}

data_map_initial :: proc(t: ^pbt.T, target: rawptr) -> Data_Map_State {
	return {}
}

data_map_command :: proc(t: ^pbt.T, state: Data_Map_State) -> Data_Map_Command {
	return {
		kind = Data_Map_Command_Kind(pbt.draw(t, pbt.int_range(0, 2))),
		key = pbt.draw(t, pbt.int_range(0, DATA_MAP_KEY_COUNT - 1)),
		value = pbt.draw(t, pbt.int_range(-10_000, 10_000)),
	}
}

data_map_run :: proc(t: ^pbt.T, target: rawptr, state: Data_Map_State, command: Data_Map_Command) -> Data_Map_Observation {
	target_path := os.get_env("KVIST_PBT_DATA_MAP_TARGET", t.value_allocator)
	if target_path == "" {
		return {error = "KVIST_PBT_DATA_MAP_TARGET is not set"}
	}

	request := fmt.tprintf(
		"[%s :%s :k%d %d]",
		data_map_state_edn(state),
		data_map_command_name(command),
		command.key,
		command.value,
	)
	command_line := [?]string{target_path}
	result := pbt.process_run_with_options(t, command_line[:], {
		stdin = request,
		timeout_ms = 1_000,
		max_output_bytes = 16_384,
	})
	if !result.success {
		error := result.error
		if result.stderr != "" {
			error = result.stderr
		} else if error == "" {
			error = fmt.tprintf("target exited with %d", result.exit_code)
		}
		return {raw = result.stdout, error = error}
	}

	parts := strings.split(result.stdout, "\t", t.value_allocator)
	if len(parts) != DATA_MAP_KEY_COUNT * 2 + 1 {
		return {
			raw = result.stdout,
			error = fmt.tprintf("target returned %d fields, expected %d", len(parts), DATA_MAP_KEY_COUNT * 2 + 1),
		}
	}

	observation := Data_Map_Observation{success = true, raw = result.stdout}
	for key in 0 ..< DATA_MAP_KEY_COUNT {
		present, present_ok := strconv.parse_int(parts[key * 2], 10)
		value, value_ok := strconv.parse_int(parts[key * 2 + 1], 10)
		if !present_ok || (present != 0 && present != 1) || !value_ok {
			return {
				raw = result.stdout,
				error = fmt.tprintf("invalid slot %d in target response", key),
			}
		}
		observation.present[key] = present == 1
		observation.values[key] = value
	}
	observation.canonical = parts[len(parts) - 1]
	return observation
}

data_map_next_state :: proc(state: Data_Map_State, command: Data_Map_Command, value: Data_Map_Observation) -> Data_Map_State {
	next := state
	switch command.kind {
	case .Assoc:
		next.present[command.key] = true
		next.values[command.key] = command.value
	case .Dissoc:
		next.present[command.key] = false
		next.values[command.key] = 0
	case .Lookup:
	}
	return next
}

data_map_postcondition :: proc(state: Data_Map_State, command: Data_Map_Command, observation: Data_Map_Observation) -> pbt.Result {
	if !observation.success {
		return pbt.fail(observation.error)
	}
	expected := data_map_next_state(state, command, observation)
	for key in 0 ..< DATA_MAP_KEY_COUNT {
		if observation.present[key] != expected.present[key] {
			return pbt.fail(fmt.tprintf(
				"%s :k%d presence mismatch: expected=%v actual=%v canonical=%s",
				data_map_command_name(command),
				key,
				expected.present[key],
				observation.present[key],
				observation.canonical,
			))
		}
		if expected.present[key] && observation.values[key] != expected.values[key] {
			return pbt.fail(fmt.tprintf(
				"%s :k%d value mismatch: expected=%d actual=%d canonical=%s",
				data_map_command_name(command),
				key,
				expected.values[key],
				observation.values[key],
				observation.canonical,
			))
		}
	}
	return pbt.pass()
}

data_map_invariant :: proc(t: ^pbt.T, state: Data_Map_State) -> pbt.Result {
	for key in 0 ..< DATA_MAP_KEY_COUNT {
		if !state.present[key] && state.values[key] != 0 {
			return pbt.fail(fmt.tprintf("absent model key :k%d retained value %d", key, state.values[key]))
		}
	}
	return pbt.pass()
}

data_map_command_name :: proc(command: Data_Map_Command) -> string {
	switch command.kind {
	case .Assoc:
		return "assoc"
	case .Dissoc:
		return "dissoc"
	case .Lookup:
		return "lookup"
	}
	return "unknown"
}

data_map_state_edn :: proc(state: Data_Map_State) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	strings.write_byte(&builder, '{')
	first := true
	for key in 0 ..< DATA_MAP_KEY_COUNT {
		if !state.present[key] {
			continue
		}
		if !first {
			strings.write_byte(&builder, ' ')
		}
		fmt.sbprintf(&builder, ":k%d %d", key, state.values[key])
		first = false
	}
	strings.write_byte(&builder, '}')
	return strings.to_string(builder)
}

data_map_state_detail :: proc(state: Data_Map_State) -> string {
	return data_map_state_edn(state)
}

data_map_value_detail :: proc(value: Data_Map_Observation) -> string {
	if !value.success {
		return fmt.tprintf("error=%s raw=%q", value.error, value.raw)
	}
	return fmt.tprintf("canonical=%s", value.canonical)
}
