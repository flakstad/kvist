// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Data_Set_State :: struct {
	mask: u16,
}

Data_Set_Command_Kind :: enum {
	Conj,
	Append,
	Probe,
	Vec_Roundtrip,
	List_Roundtrip,
}

Data_Set_Command :: struct {
	kind:  Data_Set_Command_Kind,
	value: int,
}

Data_Set_Observation :: struct {
	success:         bool,
	mask:            u16,
	count:           int,
	conversion_kind: int,
	canonical:       string,
	raw:             string,
	error:           string,
}

Data_Set_Coverage :: struct {
	conj_new:          bool,
	conj_duplicate:    bool,
	append_new:        bool,
	append_duplicate:  bool,
	probe_present:     bool,
	probe_missing:     bool,
	vector_conversion: bool,
	list_conversion:   bool,
}

data_set_commands_match_bitmask_model :: proc(t: ^pbt.T) -> pbt.Result {
	coverage: Data_Set_Coverage
	model := pbt.State_Model(Data_Set_State, Data_Set_Command, Data_Set_Observation) {
		target = &coverage,
		initial = data_set_initial,
		command = data_set_command,
		run = data_set_run,
		next_state = data_set_next_state,
		postcondition = data_set_postcondition,
		invariant = data_set_invariant,
		command_name = data_set_command_name,
		state_detail = data_set_state_detail,
		value_detail = data_set_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 1,
		max_len = 12,
		skip_success_events = true,
	})
	pbt.cover(t, coverage.conj_new, 8, "conj-new-member")
	pbt.cover(t, coverage.conj_duplicate, 3, "conj-duplicate")
	pbt.cover(t, coverage.append_new, 8, "append-new-member")
	pbt.cover(t, coverage.append_duplicate, 3, "append-duplicate")
	pbt.cover(t, coverage.probe_present, 3, "probe-present")
	pbt.cover(t, coverage.probe_missing, 8, "probe-missing")
	pbt.cover(t, coverage.vector_conversion, 20, "vector-roundtrip")
	pbt.cover(t, coverage.list_conversion, 20, "list-roundtrip")
	return result
}

data_set_initial :: proc(t: ^pbt.T, target: rawptr) -> Data_Set_State {
	return {}
}

data_set_command :: proc(t: ^pbt.T, state: Data_Set_State) -> Data_Set_Command {
	return {
		kind = Data_Set_Command_Kind(pbt.draw(t, pbt.int_range(0, 4))),
		value = pbt.draw(t, pbt.int_range(SET_VALUE_MIN, SET_VALUE_MAX)),
	}
}

data_set_run :: proc(t: ^pbt.T, target: rawptr, state: Data_Set_State, command: Data_Set_Command) -> Data_Set_Observation {
	coverage := cast(^Data_Set_Coverage)target
	bit := set_value_bit(command.value)
	present := state.mask & bit != 0
	switch command.kind {
	case .Conj:
		coverage.conj_new = coverage.conj_new || !present
		coverage.conj_duplicate = coverage.conj_duplicate || present
	case .Append:
		coverage.append_new = coverage.append_new || !present
		coverage.append_duplicate = coverage.append_duplicate || present
	case .Probe:
		coverage.probe_present = coverage.probe_present || present
		coverage.probe_missing = coverage.probe_missing || !present
	case .Vec_Roundtrip:
		coverage.vector_conversion = true
	case .List_Roundtrip:
		coverage.list_conversion = true
	}

	target_path := os.get_env("KVIST_PBT_DATA_SET_TARGET", t.value_allocator)
	if target_path == "" {
		return {error = "KVIST_PBT_DATA_SET_TARGET is not set"}
	}
	request := fmt.tprintf(
		"[%s :%s %d]",
		data_set_state_edn(state),
		data_set_command_name(command),
		command.value,
	)
	pbt.note(t, fmt.tprintf("request=%s", request))
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
	expected_fields := SET_DOMAIN_SIZE + 3
	if len(parts) != expected_fields {
		return {
			raw = result.stdout,
			error = fmt.tprintf("target returned %d fields, expected %d", len(parts), expected_fields),
		}
	}
	count, count_ok := strconv.parse_int(parts[0], 10)
	if !count_ok || count < 0 {
		return {raw = result.stdout, error = "invalid Data set count"}
	}
	observation := Data_Set_Observation{success = true, count = count, raw = result.stdout}
	for bit_index in 0 ..< SET_DOMAIN_SIZE {
		member, ok := strconv.parse_int(parts[bit_index + 1], 10)
		if !ok || (member != 0 && member != 1) {
			return {raw = result.stdout, error = fmt.tprintf("invalid member bit %d", bit_index)}
		}
		if member == 1 {
			observation.mask |= u16(1) << u64(bit_index)
		}
	}
	conversion_kind, conversion_ok := strconv.parse_int(parts[SET_DOMAIN_SIZE + 1], 10)
	if !conversion_ok || conversion_kind < 0 || conversion_kind > 2 {
		return {raw = result.stdout, error = "invalid conversion kind"}
	}
	observation.conversion_kind = conversion_kind
	observation.canonical = parts[SET_DOMAIN_SIZE + 2]
	return observation
}

data_set_next_state :: proc(state: Data_Set_State, command: Data_Set_Command, observation: Data_Set_Observation) -> Data_Set_State {
	next := state
	switch command.kind {
	case .Conj, .Append:
		next.mask |= set_value_bit(command.value)
	case .Probe, .Vec_Roundtrip, .List_Roundtrip:
	}
	return next
}

data_set_postcondition :: proc(state: Data_Set_State, command: Data_Set_Command, observation: Data_Set_Observation) -> pbt.Result {
	if !observation.success {
		return pbt.fail(observation.error)
	}
	expected := data_set_next_state(state, command, observation)
	expected_conversion := 0
	switch command.kind {
	case .Vec_Roundtrip:
		expected_conversion = 1
	case .List_Roundtrip:
		expected_conversion = 2
	case .Conj, .Append, .Probe:
	}
	if observation.mask != expected.mask || observation.count != set_mask_count(expected.mask) ||
	   observation.conversion_kind != expected_conversion {
		return pbt.fail(fmt.tprintf(
			"%s mismatch: expected-mask=%d expected-count=%d expected-conversion=%d actual-mask=%d actual-count=%d actual-conversion=%d canonical=%s",
			data_set_command_name(command),
			expected.mask,
			set_mask_count(expected.mask),
			expected_conversion,
			observation.mask,
			observation.count,
			observation.conversion_kind,
			observation.canonical,
		))
	}
	return pbt.pass()
}

data_set_invariant :: proc(t: ^pbt.T, state: Data_Set_State) -> pbt.Result {
	if state.mask & ~SET_DOMAIN_MASK != 0 {
		return pbt.fail(fmt.tprintf("Data set model has out-of-domain mask %d", state.mask))
	}
	return pbt.pass()
}

data_set_command_name :: proc(command: Data_Set_Command) -> string {
	switch command.kind {
	case .Conj:
		return "conj"
	case .Append:
		return "append"
	case .Probe:
		return "probe"
	case .Vec_Roundtrip:
		return "vec-roundtrip"
	case .List_Roundtrip:
		return "list-roundtrip"
	}
	return "unknown"
}

data_set_state_edn :: proc(state: Data_Set_State) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	strings.write_string(&builder, "#{")
	written := 0
	for bit_index in 0 ..< SET_DOMAIN_SIZE {
		if state.mask & (u16(1) << u64(bit_index)) != 0 {
			if written > 0 {
				strings.write_byte(&builder, ' ')
			}
			fmt.sbprintf(&builder, "%d", bit_index + SET_VALUE_MIN)
			written += 1
		}
	}
	strings.write_byte(&builder, '}')
	return strings.to_string(builder)
}

data_set_state_detail :: proc(state: Data_Set_State) -> string {
	return data_set_state_edn(state)
}

data_set_value_detail :: proc(value: Data_Set_Observation) -> string {
	if !value.success {
		return fmt.tprintf("error=%s raw=%q", value.error, value.raw)
	}
	return fmt.tprintf("canonical=%s", value.canonical)
}
