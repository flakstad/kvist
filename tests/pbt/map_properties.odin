// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

MAP_KEY_MIN :: -2
MAP_KEY_MAX :: 2
MAP_KEY_COUNT :: MAP_KEY_MAX - MAP_KEY_MIN + 1
MAP_VALUE_MIN :: -9
MAP_VALUE_MAX :: 9
MAP_VALUE_COUNT :: MAP_VALUE_MAX - MAP_VALUE_MIN + 1
MAP_INPUT_CAPACITY :: 8
MAP_RESULT_NAMES := [?]string {
	"lhs input",
	"rhs input",
	"merge",
	"assoc",
	"dissoc",
	"merge!",
	"assoc!",
	"dissoc!",
	"zip",
}

Native_Map_Model :: struct {
	present: [MAP_KEY_COUNT]bool,
	values:  [MAP_KEY_COUNT]int,
}

Native_Map_Input_Stats :: struct {
	length:    int,
	has_dupes: bool,
}

Native_Map_Array_Input :: struct {
	length: int,
	values: [MAP_INPUT_CAPACITY]int,
}

native_map_operations_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	strings.write_byte(&builder, '[')
	lhs_stats: Native_Map_Input_Stats
	lhs := generated_native_map(t, &builder, &lhs_stats)
	strings.write_byte(&builder, ' ')
	rhs_stats: Native_Map_Input_Stats
	rhs := generated_native_map(t, &builder, &rhs_stats)
	probe_key := pbt.draw(t, pbt.int_range(MAP_KEY_MIN, MAP_KEY_MAX))
	probe_value := pbt.draw(t, pbt.int_range(MAP_VALUE_MIN, MAP_VALUE_MAX))
	fmt.sbprintf(&builder, " %d %d ", probe_key, probe_value)
	zip_keys := generated_native_map_array(t, &builder, MAP_KEY_MIN, MAP_KEY_MAX)
	strings.write_byte(&builder, ' ')
	zip_values := generated_native_map_array(t, &builder, MAP_VALUE_MIN, MAP_VALUE_MAX)
	strings.write_byte(&builder, ']')
	request := strings.to_string(builder)

	expected := native_map_expected(lhs, rhs, probe_key, probe_value, zip_keys, zip_values)
	native_map_coverage(t, lhs, rhs, probe_key, lhs_stats, rhs_stats, zip_keys, zip_values)
	pbt.note(t, fmt.tprintf("request=%s", request))

	target_path := os.get_env("KVIST_PBT_MAP_TARGET", t.value_allocator)
	if target_path == "" {
		return pbt.error("KVIST_PBT_MAP_TARGET is not set")
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
		return pbt.fail(fmt.tprintf("map target exited with %d", process.exit_code))
	}

	parts := strings.split(process.stdout, "\t", t.value_allocator)
	field := 0
	for expected_map, result_index in expected {
		result := parse_native_map_result(parts, &field, expected_map, MAP_RESULT_NAMES[result_index])
		if result.status != .Pass {
			return result
		}
	}

	merged := expected[2]
	keys_count, keys_count_ok := parse_native_map_int(parts, &field)
	if !keys_count_ok || keys_count != native_map_count(merged) {
		return pbt.fail(fmt.tprintf("map.keys count mismatch: expected=%d actual=%d", native_map_count(merged), keys_count))
	}
	for key_index in 0 ..< MAP_KEY_COUNT {
		present, ok := parse_native_map_int(parts, &field)
		if !ok || (present != 0 && present != 1) || (present == 1) != merged.present[key_index] {
			return pbt.fail(fmt.tprintf(
				"map.keys membership mismatch for key %d",
				key_index + MAP_KEY_MIN,
			))
		}
	}

	vals_count, vals_count_ok := parse_native_map_int(parts, &field)
	if !vals_count_ok || vals_count != native_map_count(merged) {
		return pbt.fail(fmt.tprintf("map.vals count mismatch: expected=%d actual=%d", native_map_count(merged), vals_count))
	}
	for value in MAP_VALUE_MIN ..= MAP_VALUE_MAX {
		actual_frequency, ok := parse_native_map_int(parts, &field)
		expected_frequency := native_map_value_frequency(merged, value)
		if !ok || actual_frequency != expected_frequency {
			return pbt.fail(fmt.tprintf(
				"map.vals frequency mismatch for value %d: expected=%d actual=%d",
				value,
				expected_frequency,
				actual_frequency,
			))
		}
	}

	probe_index := native_map_key_index(probe_key)
	expected_present := merged.present[probe_index]
	expected_value := merged.values[probe_index]
	contains, contains_ok := parse_native_map_int(parts, &field)
	lookup_ok, lookup_ok_valid := parse_native_map_int(parts, &field)
	lookup_value, lookup_value_ok := parse_native_map_int(parts, &field)
	default_value, default_value_ok := parse_native_map_int(parts, &field)
	if !contains_ok || !lookup_ok_valid || !lookup_value_ok || !default_value_ok ||
	   (contains == 1) != expected_present || (lookup_ok == 1) != expected_present ||
	   (expected_present && lookup_value != expected_value) ||
	   default_value != (expected_present ? expected_value : -99) {
		return pbt.fail(fmt.tprintf(
			"map lookup mismatch for key %d: expected-present=%v expected-value=%d",
			probe_key,
			expected_present,
			expected_value,
		))
	}
	if field != len(parts) {
		return pbt.fail(fmt.tprintf("map target returned %d unexpected trailing fields", len(parts) - field))
	}
	return pbt.pass()
}

generated_native_map :: proc(t: ^pbt.T, builder: ^strings.Builder, stats: ^Native_Map_Input_Stats) -> Native_Map_Model {
	result: Native_Map_Model
	stats.length = pbt.draw(t, pbt.int_range(0, MAP_INPUT_CAPACITY))
	strings.write_byte(builder, '[')
	for entry_index in 0 ..< stats.length {
		key := pbt.draw(t, pbt.int_range(MAP_KEY_MIN, MAP_KEY_MAX))
		value := pbt.draw(t, pbt.int_range(MAP_VALUE_MIN, MAP_VALUE_MAX))
		key_index := native_map_key_index(key)
		stats.has_dupes = stats.has_dupes || result.present[key_index]
		result.present[key_index] = true
		result.values[key_index] = value
		if entry_index > 0 {
			strings.write_byte(builder, ' ')
		}
		fmt.sbprintf(builder, "[%d %d]", key, value)
	}
	strings.write_byte(builder, ']')
	return result
}

generated_native_map_array :: proc(t: ^pbt.T, builder: ^strings.Builder, minimum, maximum: int) -> Native_Map_Array_Input {
	result: Native_Map_Array_Input
	result.length = pbt.draw(t, pbt.int_range(0, MAP_INPUT_CAPACITY))
	strings.write_byte(builder, '[')
	for index in 0 ..< result.length {
		result.values[index] = pbt.draw(t, pbt.int_range(minimum, maximum))
		if index > 0 {
			strings.write_byte(builder, ' ')
		}
		fmt.sbprintf(builder, "%d", result.values[index])
	}
	strings.write_byte(builder, ']')
	return result
}

native_map_expected :: proc(lhs, rhs: Native_Map_Model, probe_key, probe_value: int, zip_keys, zip_values: Native_Map_Array_Input) -> [len(MAP_RESULT_NAMES)]Native_Map_Model {
	result: [len(MAP_RESULT_NAMES)]Native_Map_Model
	result[0] = lhs
	result[1] = rhs
	result[2] = native_map_merge(lhs, rhs)
	result[3] = native_map_assoc(lhs, probe_key, probe_value)
	result[4] = native_map_dissoc(lhs, probe_key)
	result[5] = result[2]
	result[6] = result[3]
	result[7] = result[4]
	limit := zip_keys.length
	if zip_values.length < limit {
		limit = zip_values.length
	}
	for index in 0 ..< limit {
		result[8] = native_map_assoc(result[8], zip_keys.values[index], zip_values.values[index])
	}
	return result
}

native_map_assoc :: proc(model: Native_Map_Model, key, value: int) -> Native_Map_Model {
	result := model
	index := native_map_key_index(key)
	result.present[index] = true
	result.values[index] = value
	return result
}

native_map_dissoc :: proc(model: Native_Map_Model, key: int) -> Native_Map_Model {
	result := model
	index := native_map_key_index(key)
	result.present[index] = false
	result.values[index] = 0
	return result
}

native_map_merge :: proc(lhs, rhs: Native_Map_Model) -> Native_Map_Model {
	result := lhs
	for index in 0 ..< MAP_KEY_COUNT {
		if rhs.present[index] {
			result.present[index] = true
			result.values[index] = rhs.values[index]
		}
	}
	return result
}

parse_native_map_result :: proc(parts: []string, field: ^int, expected: Native_Map_Model, name: string) -> pbt.Result {
	count, count_ok := parse_native_map_int(parts, field)
	if !count_ok || count != native_map_count(expected) {
		return pbt.fail(fmt.tprintf("%s count mismatch: expected=%d actual=%d", name, native_map_count(expected), count))
	}
	for key_index in 0 ..< MAP_KEY_COUNT {
		present, present_ok := parse_native_map_int(parts, field)
		value, value_ok := parse_native_map_int(parts, field)
		if !present_ok || !value_ok || (present != 0 && present != 1) ||
		   (present == 1) != expected.present[key_index] ||
		   (expected.present[key_index] && value != expected.values[key_index]) {
			return pbt.fail(fmt.tprintf(
				"%s mismatch for key %d: expected-present=%v expected-value=%d actual-present=%d actual-value=%d",
				name,
				key_index + MAP_KEY_MIN,
				expected.present[key_index],
				expected.values[key_index],
				present,
				value,
			))
		}
	}
	return pbt.pass()
}

parse_native_map_int :: proc(parts: []string, field: ^int) -> (int, bool) {
	if field^ >= len(parts) {
		return 0, false
	}
	value, ok := strconv.parse_int(parts[field^], 10)
	field^ += 1
	return value, ok
}

native_map_key_index :: proc(key: int) -> int {
	return key - MAP_KEY_MIN
}

native_map_count :: proc(model: Native_Map_Model) -> int {
	count := 0
	for present in model.present {
		if present {
			count += 1
		}
	}
	return count
}

native_map_value_frequency :: proc(model: Native_Map_Model, value: int) -> int {
	count := 0
	for index in 0 ..< MAP_KEY_COUNT {
		if model.present[index] && model.values[index] == value {
			count += 1
		}
	}
	return count
}

native_map_array_has_dupes :: proc(values: Native_Map_Array_Input) -> bool {
	for index in 0 ..< values.length {
		for prior in 0 ..< index {
			if values.values[index] == values.values[prior] {
				return true
			}
		}
	}
	return false
}

native_map_coverage :: proc(t: ^pbt.T, lhs, rhs: Native_Map_Model, probe_key: int, lhs_stats, rhs_stats: Native_Map_Input_Stats, zip_keys, zip_values: Native_Map_Array_Input) {
	probe_present := lhs.present[native_map_key_index(probe_key)]
	overlap := false
	for index in 0 ..< MAP_KEY_COUNT {
		overlap = overlap || lhs.present[index] && rhs.present[index]
	}
	pbt.cover(t, lhs_stats.has_dupes || rhs_stats.has_dupes, 25, "duplicate-map-input")
	pbt.cover(t, overlap, 25, "overlapping-keys")
	pbt.cover(t, lhs_stats.length == 0 || rhs_stats.length == 0, 8, "empty-map-input")
	pbt.cover(t, probe_present, 20, "assoc-replaces")
	pbt.cover(t, !probe_present, 20, "assoc-adds")
	pbt.cover(t, probe_present, 20, "dissoc-present")
	pbt.cover(t, !probe_present, 20, "dissoc-missing")
	pbt.cover(t, zip_keys.length != zip_values.length, 40, "zip-length-mismatch")
	pbt.cover(t, native_map_array_has_dupes(zip_keys), 15, "zip-duplicate-keys")
}
