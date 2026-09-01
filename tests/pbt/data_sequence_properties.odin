package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

DATA_SEQUENCE_CAPACITY :: 8

Data_Sequence_Kind :: enum {
	Vector,
	List,
}

Data_Sequence_State :: struct {
	kind:   Data_Sequence_Kind,
	length: int,
	values: [DATA_SEQUENCE_CAPACITY]int,
}

Data_Sequence_Command_Kind :: enum {
	Conj,
	Append,
	Assoc,
	Pop,
	Nth,
	Peek,
	To_List,
	To_Vector,
}

Data_Sequence_Command :: struct {
	kind:  Data_Sequence_Command_Kind,
	index: int,
	value: int,
}

Data_Sequence_Observation :: struct {
	success:         bool,
	queried_present: bool,
	queried_value:   int,
	kind:            Data_Sequence_Kind,
	length:          int,
	values:          [DATA_SEQUENCE_CAPACITY]int,
	canonical:       string,
	raw:             string,
	error:           string,
}

Data_Sequence_Coverage :: struct {
	assoc:            bool,
	list_conj:        bool,
	list_append:      bool,
	list_pop:         bool,
	out_of_range_nth: bool,
	empty_peek:       bool,
	conversion:       bool,
}

data_sequence_commands_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	coverage: Data_Sequence_Coverage
	model := pbt.State_Model(Data_Sequence_State, Data_Sequence_Command, Data_Sequence_Observation) {
		target = &coverage,
		initial = data_sequence_initial,
		command = data_sequence_command,
		precondition = data_sequence_precondition,
		run = data_sequence_run,
		next_state = data_sequence_next_state,
		postcondition = data_sequence_postcondition,
		invariant = data_sequence_invariant,
		command_name = data_sequence_command_name,
		state_detail = data_sequence_state_detail,
		value_detail = data_sequence_value_detail,
	}
	result := pbt.run_commands(t, model, {
		min_len = 1,
		max_len = DATA_SEQUENCE_CAPACITY,
		skip_success_events = true,
	})
	pbt.cover(t, coverage.assoc, 3, "indexed-assoc")
	pbt.cover(t, coverage.list_conj, 2, "list-conj")
	pbt.cover(t, coverage.list_append, 2, "list-append")
	pbt.cover(t, coverage.list_pop, 1, "list-pop")
	pbt.cover(t, coverage.out_of_range_nth, 5, "out-of-range-nth")
	pbt.cover(t, coverage.empty_peek, 3, "empty-peek")
	pbt.cover(t, coverage.conversion, 15, "list-vector-conversion")
	return result
}

data_sequence_initial :: proc(t: ^pbt.T, target: rawptr) -> Data_Sequence_State {
	return {kind = .Vector}
}

data_sequence_command :: proc(t: ^pbt.T, state: Data_Sequence_State) -> Data_Sequence_Command {
	return {
		kind = Data_Sequence_Command_Kind(pbt.draw(t, pbt.int_range(0, 7))),
		index = pbt.draw(t, pbt.int_range(-1, state.length)),
		value = pbt.draw(t, pbt.int_range(-10_000, 10_000)),
	}
}

data_sequence_precondition :: proc(state: Data_Sequence_State, command: Data_Sequence_Command) -> bool {
	switch command.kind {
	case .Conj, .Append:
		return state.length < DATA_SEQUENCE_CAPACITY
	case .Assoc:
		return state.kind == .Vector && command.index >= 0 && command.index < state.length
	case .Pop:
		return state.length > 0
	case .Nth, .Peek, .To_List, .To_Vector:
		return true
	}
	return false
}

data_sequence_run :: proc(t: ^pbt.T, target: rawptr, state: Data_Sequence_State, command: Data_Sequence_Command) -> Data_Sequence_Observation {
	coverage := cast(^Data_Sequence_Coverage)target
	switch command.kind {
	case .Assoc:
		coverage.assoc = true
	case .Conj:
		coverage.list_conj = coverage.list_conj || state.kind == .List
	case .Append:
		coverage.list_append = coverage.list_append || state.kind == .List
	case .Pop:
		coverage.list_pop = coverage.list_pop || state.kind == .List
	case .Nth:
		coverage.out_of_range_nth = coverage.out_of_range_nth || command.index < 0 || command.index >= state.length
	case .Peek:
		coverage.empty_peek = coverage.empty_peek || state.length == 0
	case .To_List, .To_Vector:
		coverage.conversion = true
	}

	target_path := os.get_env("KVIST_PBT_DATA_SEQUENCE_TARGET", t.value_allocator)
	if target_path == "" {
		return {error = "KVIST_PBT_DATA_SEQUENCE_TARGET is not set"}
	}

	request := fmt.tprintf(
		"[%s :%s %d %d]",
		data_sequence_state_edn(state),
		data_sequence_command_name(command),
		command.index,
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

	field_count := 2 + 1 + 1 + DATA_SEQUENCE_CAPACITY + 1
	parts := strings.split(result.stdout, "\t", t.value_allocator)
	if len(parts) != field_count {
		return {
			raw = result.stdout,
			error = fmt.tprintf("target returned %d fields, expected %d", len(parts), field_count),
		}
	}

	observation := Data_Sequence_Observation{success = true, raw = result.stdout}
	queried_present, queried_value, query_ok := data_sequence_parse_slot(parts[0], parts[1])
	if !query_ok {
		return {raw = result.stdout, error = "invalid queried value in target response"}
	}
	observation.queried_present = queried_present
	observation.queried_value = queried_value

	kind, kind_ok := strconv.parse_int(parts[2], 10)
	length, length_ok := strconv.parse_int(parts[3], 10)
	if !kind_ok || (kind != 0 && kind != 1) ||
	   !length_ok || length < 0 || length > DATA_SEQUENCE_CAPACITY {
		return {raw = result.stdout, error = "invalid kind or length in target response"}
	}
	observation.kind = Data_Sequence_Kind(kind)
	observation.length = length
	for index in 0 ..< DATA_SEQUENCE_CAPACITY {
		value, ok := strconv.parse_int(parts[4 + index], 10)
		if !ok {
			return {
				raw = result.stdout,
				error = fmt.tprintf("invalid item %d in target response", index),
			}
		}
		observation.values[index] = value
	}
	observation.canonical = parts[len(parts) - 1]
	return observation
}

data_sequence_parse_slot :: proc(present_text, value_text: string) -> (bool, int, bool) {
	present, present_ok := strconv.parse_int(present_text, 10)
	value, value_ok := strconv.parse_int(value_text, 10)
	if !present_ok || (present != 0 && present != 1) || !value_ok {
		return false, 0, false
	}
	return present == 1, value, true
}

data_sequence_next_state :: proc(state: Data_Sequence_State, command: Data_Sequence_Command, value: Data_Sequence_Observation) -> Data_Sequence_State {
	next := state
	switch command.kind {
	case .Conj:
		if next.kind == .List {
			for index := next.length; index > 0; index -= 1 {
				next.values[index] = next.values[index - 1]
			}
			next.values[0] = command.value
		} else {
			next.values[next.length] = command.value
		}
		next.length += 1
	case .Append:
		next.values[next.length] = command.value
		next.length += 1
	case .Assoc:
		next.values[command.index] = command.value
	case .Pop:
		if next.kind == .List {
			for index in 0 ..< next.length - 1 {
				next.values[index] = next.values[index + 1]
			}
		}
		next.length -= 1
		next.values[next.length] = 0
	case .Nth, .Peek:
	case .To_List:
		next.kind = .List
	case .To_Vector:
		next.kind = .Vector
	}
	return next
}

data_sequence_expected_query :: proc(state: Data_Sequence_State, command: Data_Sequence_Command) -> (bool, int) {
	if command.kind == .Assoc || command.kind == .Nth {
		if command.index < 0 || command.index >= state.length {
			return false, 0
		}
		return true, state.values[command.index]
	}
	if state.length == 0 {
		return false, 0
	}
	if state.kind == .List {
		return true, state.values[0]
	}
	return true, state.values[state.length - 1]
}

data_sequence_postcondition :: proc(state: Data_Sequence_State, command: Data_Sequence_Command, observation: Data_Sequence_Observation) -> pbt.Result {
	if !observation.success {
		return pbt.fail(observation.error)
	}
	expected := data_sequence_next_state(state, command, observation)
	expected_present, expected_value := data_sequence_expected_query(expected, command)
	if observation.queried_present != expected_present ||
	   (expected_present && observation.queried_value != expected_value) {
		return pbt.fail(fmt.tprintf(
			"%s query mismatch: expected=%s actual=%s canonical=%s",
			data_sequence_command_name(command),
			data_sequence_slot_detail(expected_present, expected_value),
			data_sequence_slot_detail(observation.queried_present, observation.queried_value),
			observation.canonical,
		))
	}
	if observation.kind != expected.kind || observation.length != expected.length {
		return pbt.fail(fmt.tprintf(
			"%s shape mismatch: expected=%s/%d actual=%s/%d canonical=%s",
			data_sequence_command_name(command),
			data_sequence_kind_name(expected.kind),
			expected.length,
			data_sequence_kind_name(observation.kind),
			observation.length,
			observation.canonical,
		))
	}
	for index in 0 ..< expected.length {
		if observation.values[index] != expected.values[index] {
			return pbt.fail(fmt.tprintf(
				"%s item %d mismatch: expected=%d actual=%d canonical=%s",
				data_sequence_command_name(command),
				index,
				expected.values[index],
				observation.values[index],
				observation.canonical,
			))
		}
	}
	return pbt.pass()
}

data_sequence_invariant :: proc(t: ^pbt.T, state: Data_Sequence_State) -> pbt.Result {
	if state.length < 0 || state.length > DATA_SEQUENCE_CAPACITY {
		return pbt.fail(fmt.tprintf("model sequence length %d is out of bounds", state.length))
	}
	for index in state.length ..< DATA_SEQUENCE_CAPACITY {
		if state.values[index] != 0 {
			return pbt.fail(fmt.tprintf("unused model slot %d retained value %d", index, state.values[index]))
		}
	}
	return pbt.pass()
}

data_sequence_command_name :: proc(command: Data_Sequence_Command) -> string {
	switch command.kind {
	case .Conj:
		return "conj"
	case .Append:
		return "append"
	case .Assoc:
		return "assoc"
	case .Pop:
		return "pop"
	case .Nth:
		return "nth"
	case .Peek:
		return "peek"
	case .To_List:
		return "to-list"
	case .To_Vector:
		return "to-vector"
	}
	return "unknown"
}

data_sequence_kind_name :: proc(kind: Data_Sequence_Kind) -> string {
	switch kind {
	case .Vector:
		return "vector"
	case .List:
		return "list"
	}
	return "unknown"
}

data_sequence_state_edn :: proc(state: Data_Sequence_State) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	if state.kind == .List {
		strings.write_byte(&builder, '(')
	} else {
		strings.write_byte(&builder, '[')
	}
	for index in 0 ..< state.length {
		if index > 0 {
			strings.write_byte(&builder, ' ')
		}
		fmt.sbprintf(&builder, "%d", state.values[index])
	}
	if state.kind == .List {
		strings.write_byte(&builder, ')')
	} else {
		strings.write_byte(&builder, ']')
	}
	return strings.to_string(builder)
}

data_sequence_state_detail :: proc(state: Data_Sequence_State) -> string {
	return data_sequence_state_edn(state)
}

data_sequence_value_detail :: proc(value: Data_Sequence_Observation) -> string {
	if !value.success {
		return fmt.tprintf("error=%s raw=%q", value.error, value.raw)
	}
	return fmt.tprintf("canonical=%s", value.canonical)
}

data_sequence_slot_detail :: proc(present: bool, value: int) -> string {
	if !present {
		return "missing"
	}
	return fmt.tprintf("%d", value)
}
