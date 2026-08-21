// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

DATA_AGGREGATE_VALUE_MIN :: -5
DATA_AGGREGATE_VALUE_MAX :: 5
DATA_AGGREGATE_VALUE_COUNT :: DATA_AGGREGATE_VALUE_MAX - DATA_AGGREGATE_VALUE_MIN + 1
DATA_AGGREGATE_GROUP_MIN :: -3
DATA_AGGREGATE_GROUP_MAX :: 3
DATA_AGGREGATE_GROUP_COUNT :: DATA_AGGREGATE_GROUP_MAX - DATA_AGGREGATE_GROUP_MIN + 1
DATA_AGGREGATE_CAPACITY :: 10

Data_Aggregate_Input :: struct {
	length: int,
	values: [DATA_AGGREGATE_CAPACITY]int,
}

Data_Aggregate_Model :: struct {
	sum:             int,
	fold:            int,
	frequencies:     [DATA_AGGREGATE_VALUE_COUNT]int,
	group_counts:    [DATA_AGGREGATE_GROUP_COUNT]int,
	group_values:    [DATA_AGGREGATE_GROUP_COUNT * DATA_AGGREGATE_CAPACITY]int,
	index_present:   [DATA_AGGREGATE_GROUP_COUNT]bool,
	index_values:    [DATA_AGGREGATE_GROUP_COUNT]int,
	distinct_values: int,
	distinct_groups: int,
}

Data_Aggregate_Input_Stats :: struct {
	has_dupes:    bool,
	has_negative: bool,
}

data_aggregates_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	stats: Data_Aggregate_Input_Stats
	input := generated_aggregate_input(t, &stats)
	divisor := pbt.draw(t, pbt.int_range(1, 4))
	seed := pbt.draw(t, pbt.int_range(-3, 3))
	multiplier := pbt.draw(t, pbt.int_range(2, 4))
	expected := data_aggregate_model(input, divisor, seed, multiplier)
	data_aggregate_coverage(t, input, expected, divisor, seed, stats)
	request := data_aggregate_request(input, divisor, seed, multiplier)
	pbt.note(t, fmt.tprintf("request=%s", request))

	target_path := os.get_env("KVIST_PBT_DATA_AGGREGATE_TARGET", t.value_allocator)
	if target_path == "" {
		return pbt.error("KVIST_PBT_DATA_AGGREGATE_TARGET is not set")
	}
	command := [?]string{target_path}
	process := pbt.process_run_with_options(t, command[:], {
		stdin = request,
		timeout_ms = 1_000,
		max_output_bytes = 32_768,
	})
	if !process.success {
		if process.stderr != "" {
			return pbt.fail(process.stderr)
		}
		if process.error != "" {
			return pbt.fail(process.error)
		}
		return pbt.fail(fmt.tprintf("Data aggregate target exited with %d", process.exit_code))
	}

	parts := strings.split(process.stdout, "\t", t.value_allocator)
	field := 0
	scalar_names := [?]string{"reduce-sum", "reduce-fold", "frequency-total", "frequency-weighted-sum"}
	scalar_expected := [?]int{expected.sum, expected.fold, input.length, expected.sum - seed}
	for name, scalar_index in scalar_names {
		actual, ok := parse_data_aggregate_int(parts, &field)
		if !ok || actual != scalar_expected[scalar_index] {
			return pbt.fail(fmt.tprintf(
				"%s mismatch: expected=%d actual=%d",
				name,
				scalar_expected[scalar_index],
				actual,
			))
		}
	}

	frequency_count, frequency_count_ok := parse_data_aggregate_int(parts, &field)
	if !frequency_count_ok || frequency_count != expected.distinct_values {
		return pbt.fail(fmt.tprintf(
			"frequencies cardinality mismatch: expected=%d actual=%d",
			expected.distinct_values,
			frequency_count,
		))
	}
	for value_index in 0 ..< DATA_AGGREGATE_VALUE_COUNT {
		actual, ok := parse_data_aggregate_int(parts, &field)
		if !ok || actual != expected.frequencies[value_index] {
			return pbt.fail(fmt.tprintf(
				"frequency mismatch for value %d: expected=%d actual=%d",
				value_index + DATA_AGGREGATE_VALUE_MIN,
				expected.frequencies[value_index],
				actual,
			))
		}
	}

	count_by_count, count_by_count_ok := parse_data_aggregate_int(parts, &field)
	if !count_by_count_ok || count_by_count != expected.distinct_groups {
		return pbt.fail(fmt.tprintf(
			"count-by cardinality mismatch: expected=%d actual=%d",
			expected.distinct_groups,
			count_by_count,
		))
	}
	for group_index in 0 ..< DATA_AGGREGATE_GROUP_COUNT {
		actual, ok := parse_data_aggregate_int(parts, &field)
		if !ok || actual != expected.group_counts[group_index] {
			return pbt.fail(fmt.tprintf(
				"count-by mismatch for key %d: expected=%d actual=%d",
				group_index + DATA_AGGREGATE_GROUP_MIN,
				expected.group_counts[group_index],
				actual,
			))
		}
	}

	index_result := parse_data_index_by(parts, &field, expected)
	if index_result.status != .Pass {
		return index_result
	}
	group_result := parse_data_group_by(parts, &field, expected)
	if group_result.status != .Pass {
		return group_result
	}
	if field >= len(parts) || parts[field] != "done" || field + 1 != len(parts) {
		return pbt.fail(fmt.tprintf("unexpected aggregate target trailer: %q", process.stdout))
	}
	return pbt.pass()
}

generated_aggregate_input :: proc(t: ^pbt.T, stats: ^Data_Aggregate_Input_Stats) -> Data_Aggregate_Input {
	result: Data_Aggregate_Input
	result.length = pbt.draw(t, pbt.int_range(0, DATA_AGGREGATE_CAPACITY))
	for index in 0 ..< result.length {
		value := pbt.draw(t, pbt.int_range(DATA_AGGREGATE_VALUE_MIN, DATA_AGGREGATE_VALUE_MAX))
		stats.has_negative = stats.has_negative || value < 0
		for prior in 0 ..< index {
			stats.has_dupes = stats.has_dupes || result.values[prior] == value
		}
		result.values[index] = value
	}
	return result
}

data_aggregate_model :: proc(input: Data_Aggregate_Input, divisor, seed, multiplier: int) -> Data_Aggregate_Model {
	result := Data_Aggregate_Model{sum = seed, fold = seed}
	for index in 0 ..< input.length {
		value := input.values[index]
		result.sum += value
		result.fold = result.fold * multiplier + value
		value_index := value - DATA_AGGREGATE_VALUE_MIN
		if result.frequencies[value_index] == 0 {
			result.distinct_values += 1
		}
		result.frequencies[value_index] += 1

		group := value % divisor
		group_index := group - DATA_AGGREGATE_GROUP_MIN
		position := result.group_counts[group_index]
		if position == 0 {
			result.distinct_groups += 1
		}
		result.group_values[group_index * DATA_AGGREGATE_CAPACITY + position] = value
		result.group_counts[group_index] += 1
		result.index_present[group_index] = true
		result.index_values[group_index] = value
	}
	return result
}

data_aggregate_request :: proc(input: Data_Aggregate_Input, divisor, seed, multiplier: int) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	strings.write_byte(&builder, '[')
	strings.write_byte(&builder, '[')
	for index in 0 ..< input.length {
		if index > 0 {
			strings.write_byte(&builder, ' ')
		}
		fmt.sbprintf(&builder, "%d", input.values[index])
	}
	strings.write_byte(&builder, ']')
	fmt.sbprintf(&builder, " %d %d %d]", divisor, seed, multiplier)
	return strings.to_string(builder)
}

parse_data_index_by :: proc(parts: []string, field: ^int, expected: Data_Aggregate_Model) -> pbt.Result {
	cardinality, cardinality_ok := parse_data_aggregate_int(parts, field)
	if !cardinality_ok || cardinality != expected.distinct_groups {
		return pbt.fail(fmt.tprintf(
			"index-by cardinality mismatch: expected=%d actual=%d",
			expected.distinct_groups,
			cardinality,
		))
	}
	for group_index in 0 ..< DATA_AGGREGATE_GROUP_COUNT {
		present, present_ok := parse_data_aggregate_int(parts, field)
		value, value_ok := parse_data_aggregate_int(parts, field)
		if !present_ok || !value_ok || (present != 0 && present != 1) ||
		   (present == 1) != expected.index_present[group_index] ||
		   (expected.index_present[group_index] && value != expected.index_values[group_index]) {
			return pbt.fail(fmt.tprintf(
				"index-by mismatch for key %d: expected-present=%v expected-value=%d actual-present=%d actual-value=%d",
				group_index + DATA_AGGREGATE_GROUP_MIN,
				expected.index_present[group_index],
				expected.index_values[group_index],
				present,
				value,
			))
		}
	}
	return pbt.pass()
}

parse_data_group_by :: proc(parts: []string, field: ^int, expected: Data_Aggregate_Model) -> pbt.Result {
	cardinality, cardinality_ok := parse_data_aggregate_int(parts, field)
	if !cardinality_ok || cardinality != expected.distinct_groups {
		return pbt.fail(fmt.tprintf(
			"group-by cardinality mismatch: expected=%d actual=%d",
			expected.distinct_groups,
			cardinality,
		))
	}
	for group_index in 0 ..< DATA_AGGREGATE_GROUP_COUNT {
		present, present_ok := parse_data_aggregate_int(parts, field)
		length, length_ok := parse_data_aggregate_int(parts, field)
		expected_length := expected.group_counts[group_index]
		if !present_ok || !length_ok || (present != 0 && present != 1) ||
		   (present == 1) != (expected_length > 0) || length != expected_length {
			return pbt.fail(fmt.tprintf(
				"group-by shape mismatch for key %d: expected-length=%d actual-present=%d actual-length=%d",
				group_index + DATA_AGGREGATE_GROUP_MIN,
				expected_length,
				present,
				length,
			))
		}
		for item_index in 0 ..< length {
			actual, ok := parse_data_aggregate_int(parts, field)
			expected_value := expected.group_values[group_index * DATA_AGGREGATE_CAPACITY + item_index]
			if !ok || actual != expected_value {
				return pbt.fail(fmt.tprintf(
					"group-by item mismatch for key %d at %d: expected=%d actual=%d",
					group_index + DATA_AGGREGATE_GROUP_MIN,
					item_index,
					expected_value,
					actual,
				))
			}
		}
	}
	return pbt.pass()
}

parse_data_aggregate_int :: proc(parts: []string, field: ^int) -> (int, bool) {
	if field^ >= len(parts) {
		return 0, false
	}
	value, ok := strconv.parse_int(parts[field^], 10)
	field^ += 1
	return value, ok
}

data_aggregate_coverage :: proc(t: ^pbt.T, input: Data_Aggregate_Input, expected: Data_Aggregate_Model, divisor, seed: int, stats: Data_Aggregate_Input_Stats) {
	pbt.cover(t, input.length == 0, 5, "empty-input")
	pbt.cover(t, stats.has_dupes, 20, "duplicate-input")
	pbt.cover(t, stats.has_negative, 30, "negative-values")
	pbt.cover(t, divisor > 1, 50, "multi-key-grouping")
	pbt.cover(t, expected.distinct_groups > 1, 25, "multiple-groups")
	pbt.cover(t, input.length > expected.distinct_groups, 30, "group-collisions")
	pbt.cover(t, seed != 0, 60, "non-zero-reduce-seed")
}
