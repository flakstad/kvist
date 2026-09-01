package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

DATA_NESTED_OUTER_COUNT :: 2
DATA_NESTED_INNER_COUNT :: 3
DATA_NESTED_SLOT_COUNT :: DATA_NESTED_OUTER_COUNT * DATA_NESTED_INNER_COUNT

Data_Nested_State :: struct {
	parent_present: [DATA_NESTED_OUTER_COUNT]bool,
	present:        [DATA_NESTED_SLOT_COUNT]bool,
	values:         [DATA_NESTED_SLOT_COUNT]int,
}

Data_Nested_Command_Kind :: enum {
	Assoc_In,
	Update_In,
	Get_In,
	Dissoc_In,
}

Data_Nested_Command :: struct {
	kind:  Data_Nested_Command_Kind,
	outer: int,
	inner: int,
	value: int,
}

Data_Nested_Observation :: struct {
	success:         bool,
	queried_present: bool,
	queried_value:   int,
	parent_present:  [DATA_NESTED_OUTER_COUNT]bool,
	parent_counts:   [DATA_NESTED_OUTER_COUNT]int,
	parent_maps:     [DATA_NESTED_OUTER_COUNT]bool,
	present:         [DATA_NESTED_SLOT_COUNT]bool,
	values:          [DATA_NESTED_SLOT_COUNT]int,
	canonical:       string,
	raw:             string,
	error:           string,
}

Data_Nested_Coverage :: struct {
	dissoc_existing:    bool,
	dissoc_missing:     bool,
	preserved_empty:    bool,
	preserved_siblings: bool,
}

data_nested_commands_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	coverage: Data_Nested_Coverage
	model := pbt.State_Model(Data_Nested_State, Data_Nested_Command, Data_Nested_Observation) {
		target = &coverage,
		initial = data_nested_initial,
		command = data_nested_command,
		run = data_nested_run,
		next_state = data_nested_next_state,
		postcondition = data_nested_postcondition,
		invariant = data_nested_invariant,
		command_name = data_nested_command_name,
		state_detail = data_nested_state_detail,
		value_detail = data_nested_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 1,
		max_len = 12,
		skip_success_events = true,
	})
	pbt.cover(t, coverage.dissoc_existing, 3, "dissoc-existing-path")
	pbt.cover(t, coverage.dissoc_missing, 15, "dissoc-missing-path")
	pbt.cover(t, coverage.preserved_empty, 1, "dissoc-preserves-empty-parent")
	pbt.cover(t, coverage.preserved_siblings, 1, "dissoc-preserves-siblings")
	return result
}

data_nested_initial :: proc(t: ^pbt.T, target: rawptr) -> Data_Nested_State {
	return {}
}

data_nested_command :: proc(t: ^pbt.T, state: Data_Nested_State) -> Data_Nested_Command {
	return {
		kind = Data_Nested_Command_Kind(pbt.draw(t, pbt.int_range(0, 3))),
		outer = pbt.draw(t, pbt.int_range(0, DATA_NESTED_OUTER_COUNT - 1)),
		inner = pbt.draw(t, pbt.int_range(0, DATA_NESTED_INNER_COUNT - 1)),
		value = pbt.draw(t, pbt.int_range(-10_000, 10_000)),
	}
}

data_nested_run :: proc(t: ^pbt.T, target: rawptr, state: Data_Nested_State, command: Data_Nested_Command) -> Data_Nested_Observation {
	coverage := cast(^Data_Nested_Coverage)target
	if command.kind == .Dissoc_In {
		slot := data_nested_index(command.outer, command.inner)
		child_count := data_nested_child_count(state, command.outer)
		coverage.dissoc_existing = coverage.dissoc_existing || state.present[slot]
		coverage.dissoc_missing = coverage.dissoc_missing || !state.present[slot]
		coverage.preserved_empty = coverage.preserved_empty || state.present[slot] && child_count == 1
		coverage.preserved_siblings = coverage.preserved_siblings || state.present[slot] && child_count > 1
	}
	target_path := os.get_env("KVIST_PBT_DATA_NESTED_TARGET", t.value_allocator)
	if target_path == "" {
		return {error = "KVIST_PBT_DATA_NESTED_TARGET is not set"}
	}

	request := fmt.tprintf(
		"[%s :%s :o%d :i%d %d]",
		data_nested_state_edn(state),
		data_nested_command_name(command),
		command.outer,
		command.inner,
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

	field_count := (DATA_NESTED_SLOT_COUNT + 1) * 2 + DATA_NESTED_OUTER_COUNT * 3 + 1
	parts := strings.split(result.stdout, "\t", t.value_allocator)
	if len(parts) != field_count {
		return {
			raw = result.stdout,
			error = fmt.tprintf("target returned %d fields, expected %d", len(parts), field_count),
		}
	}

	observation := Data_Nested_Observation{success = true, raw = result.stdout}
	queried_present, queried_value, ok := data_nested_parse_slot(parts[0], parts[1])
	if !ok {
		return {raw = result.stdout, error = "invalid queried value in target response"}
	}
	observation.queried_present = queried_present
	observation.queried_value = queried_value
	field := 2
	for outer in 0 ..< DATA_NESTED_OUTER_COUNT {
		for inner in 0 ..< DATA_NESTED_INNER_COUNT {
			slot := data_nested_index(outer, inner)
			present, value, slot_ok := data_nested_parse_slot(parts[field], parts[field + 1])
			if !slot_ok {
				return {
					raw = result.stdout,
					error = fmt.tprintf("invalid :o%d/:i%d slot in target response", outer, inner),
				}
			}
			observation.present[slot] = present
			observation.values[slot] = value
			field += 2
		}
	}
	for outer in 0 ..< DATA_NESTED_OUTER_COUNT {
		parent_present, parent_present_ok := strconv.parse_int(parts[field], 10)
		parent_count, parent_count_ok := strconv.parse_int(parts[field + 1], 10)
		parent_map, parent_map_ok := strconv.parse_int(parts[field + 2], 10)
		if !parent_present_ok || (parent_present != 0 && parent_present != 1) ||
		   !parent_count_ok || parent_count < 0 ||
		   !parent_map_ok || (parent_map != 0 && parent_map != 1) {
			return {
				raw = result.stdout,
				error = fmt.tprintf("invalid :o%d parent in target response", outer),
			}
		}
		observation.parent_present[outer] = parent_present == 1
		observation.parent_counts[outer] = parent_count
		observation.parent_maps[outer] = parent_map == 1
		field += 3
	}
	observation.canonical = parts[field]
	return observation
}

data_nested_parse_slot :: proc(present_text, value_text: string) -> (bool, int, bool) {
	present, present_ok := strconv.parse_int(present_text, 10)
	value, value_ok := strconv.parse_int(value_text, 10)
	if !present_ok || (present != 0 && present != 1) || !value_ok {
		return false, 0, false
	}
	return present == 1, value, true
}

data_nested_next_state :: proc(state: Data_Nested_State, command: Data_Nested_Command, value: Data_Nested_Observation) -> Data_Nested_State {
	next := state
	slot := data_nested_index(command.outer, command.inner)
	switch command.kind {
	case .Assoc_In:
		next.parent_present[command.outer] = true
		next.present[slot] = true
		next.values[slot] = command.value
	case .Update_In:
		next.parent_present[command.outer] = true
		if next.present[slot] {
			next.values[slot] += 1
		} else {
			next.present[slot] = true
			next.values[slot] = 1
		}
	case .Dissoc_In:
		next.present[slot] = false
		next.values[slot] = 0
	case .Get_In:
	}
	return next
}

data_nested_postcondition :: proc(state: Data_Nested_State, command: Data_Nested_Command, observation: Data_Nested_Observation) -> pbt.Result {
	if !observation.success {
		return pbt.fail(observation.error)
	}
	expected := data_nested_next_state(state, command, observation)
	command_slot := data_nested_index(command.outer, command.inner)
	expected_present := expected.present[command_slot]
	expected_value := expected.values[command_slot]
	if observation.queried_present != expected_present ||
	   (expected_present && observation.queried_value != expected_value) {
		return pbt.fail(fmt.tprintf(
			"%s :o%d/:i%d result mismatch: expected=%s actual=%s canonical=%s",
			data_nested_command_name(command),
			command.outer,
			command.inner,
			data_nested_slot_detail(expected_present, expected_value),
			data_nested_slot_detail(observation.queried_present, observation.queried_value),
			observation.canonical,
		))
	}
	for outer in 0 ..< DATA_NESTED_OUTER_COUNT {
		expected_count := data_nested_child_count(expected, outer)
		if observation.parent_present[outer] != expected.parent_present[outer] ||
		   observation.parent_counts[outer] != expected_count ||
		   observation.parent_maps[outer] != expected.parent_present[outer] {
			return pbt.fail(fmt.tprintf(
				"%s :o%d parent mismatch: expected-present=%v expected-count=%d actual-present=%v actual-count=%d actual-map=%v canonical=%s",
				data_nested_command_name(command),
				outer,
				expected.parent_present[outer],
				expected_count,
				observation.parent_present[outer],
				observation.parent_counts[outer],
				observation.parent_maps[outer],
				observation.canonical,
			))
		}
		for inner in 0 ..< DATA_NESTED_INNER_COUNT {
			slot := data_nested_index(outer, inner)
			if observation.present[slot] != expected.present[slot] ||
			   (expected.present[slot] && observation.values[slot] != expected.values[slot]) {
				return pbt.fail(fmt.tprintf(
					"%s :o%d/:i%d state mismatch: expected=%s actual=%s canonical=%s",
					data_nested_command_name(command),
					outer,
					inner,
					data_nested_slot_detail(expected.present[slot], expected.values[slot]),
					data_nested_slot_detail(observation.present[slot], observation.values[slot]),
					observation.canonical,
				))
			}
		}
	}
	return pbt.pass()
}

data_nested_invariant :: proc(t: ^pbt.T, state: Data_Nested_State) -> pbt.Result {
	for outer in 0 ..< DATA_NESTED_OUTER_COUNT {
		for inner in 0 ..< DATA_NESTED_INNER_COUNT {
			slot := data_nested_index(outer, inner)
			if state.present[slot] && !state.parent_present[outer] {
				return pbt.fail(fmt.tprintf(
					"present model path :o%d/:i%d has no parent",
					outer,
					inner,
				))
			}
			if !state.present[slot] && state.values[slot] != 0 {
				return pbt.fail(fmt.tprintf(
					"absent model path :o%d/:i%d retained value %d",
					outer,
					inner,
					state.values[slot],
				))
			}
		}
	}
	return pbt.pass()
}

data_nested_command_name :: proc(command: Data_Nested_Command) -> string {
	switch command.kind {
	case .Assoc_In:
		return "assoc-in"
	case .Update_In:
		return "update-in"
	case .Get_In:
		return "get-in"
	case .Dissoc_In:
		return "dissoc-in"
	}
	return "unknown"
}

data_nested_state_edn :: proc(state: Data_Nested_State) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	strings.write_byte(&builder, '{')
	first_outer := true
	for outer in 0 ..< DATA_NESTED_OUTER_COUNT {
		if !state.parent_present[outer] {
			continue
		}
		if !first_outer {
			strings.write_byte(&builder, ' ')
		}
		fmt.sbprintf(&builder, ":o%d ", outer)
		strings.write_byte(&builder, '{')
		first_inner := true
		for inner in 0 ..< DATA_NESTED_INNER_COUNT {
			slot := data_nested_index(outer, inner)
			if !state.present[slot] {
				continue
			}
			if !first_inner {
				strings.write_byte(&builder, ' ')
			}
			fmt.sbprintf(&builder, ":i%d %d", inner, state.values[slot])
			first_inner = false
		}
		strings.write_byte(&builder, '}')
		first_outer = false
	}
	strings.write_byte(&builder, '}')
	return strings.to_string(builder)
}

data_nested_state_detail :: proc(state: Data_Nested_State) -> string {
	return data_nested_state_edn(state)
}

data_nested_value_detail :: proc(value: Data_Nested_Observation) -> string {
	if !value.success {
		return fmt.tprintf("error=%s raw=%q", value.error, value.raw)
	}
	return fmt.tprintf("canonical=%s", value.canonical)
}

data_nested_slot_detail :: proc(present: bool, value: int) -> string {
	if !present {
		return "missing"
	}
	return fmt.tprintf("%d", value)
}

data_nested_index :: proc(outer, inner: int) -> int {
	return outer * DATA_NESTED_INNER_COUNT + inner
}

data_nested_child_count :: proc(state: Data_Nested_State, outer: int) -> int {
	count := 0
	for inner in 0 ..< DATA_NESTED_INNER_COUNT {
		if state.present[data_nested_index(outer, inner)] {
			count += 1
		}
	}
	return count
}
