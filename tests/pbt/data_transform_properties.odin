// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

DATA_TRANSFORM_INPUT_CAPACITY :: 8
DATA_TRANSFORM_RESULT_CAPACITY :: DATA_TRANSFORM_INPUT_CAPACITY * 2
DATA_TRANSFORM_VALUE_MIN :: -5
DATA_TRANSFORM_VALUE_MAX :: 5
DATA_TRANSFORM_VALUE_COUNT :: DATA_TRANSFORM_VALUE_MAX - DATA_TRANSFORM_VALUE_MIN + 1
DATA_TRANSFORM_NAMES := [?]string {
	"input",
	"map",
	"map-indexed",
	"filter",
	"take",
	"drop",
	"reverse",
	"distinct",
	"split-left",
	"split-right",
	"interpose",
	"take-nth",
	"concat-split",
	"reverse-twice",
	"remove",
	"keep",
	"keep-indexed",
	"mapcat",
	"distinct-by",
	"interleave",
	"rest",
	"butlast",
	"into-vector",
	"into-list",
}

Data_Transform_Sequence :: struct {
	length: int,
	values: [DATA_TRANSFORM_RESULT_CAPACITY]int,
}

Data_Transform_Input_Stats :: struct {
	has_dupes: bool,
}

Data_Transform_Set :: struct {
	count:   int,
	present: [DATA_TRANSFORM_VALUE_COUNT]bool,
}

data_transforms_match_sequence_model :: proc(t: ^pbt.T) -> pbt.Result {
	input_stats: Data_Transform_Input_Stats
	input := generated_transform_input(t, &input_stats)
	other_stats: Data_Transform_Input_Stats
	other := generated_transform_input(t, &other_stats)
	n := pbt.draw(t, pbt.int_range(-3, DATA_TRANSFORM_INPUT_CAPACITY + 3))
	offset := pbt.draw(t, pbt.int_range(-5, 5))
	threshold := pbt.draw(t, pbt.int_range(-5, 5))
	separator := pbt.draw(t, pbt.int_range(-5, 5))
	step := pbt.draw(t, pbt.int_range(-1, 4))
	divisor := pbt.draw(t, pbt.int_range(1, 4))
	probe := pbt.draw(t, pbt.int_range(-5, 5))

	expected := data_transform_expected(input, other, n, offset, threshold, separator, step, divisor)
	expected_includes := data_transform_contains(input, probe)
	expected_set := data_transform_set_union(input, other)
	data_transform_coverage(t, input, other, expected, expected_set, n, offset, step, input_stats, other_stats, expected_includes)
	request := data_transform_request(input, other, n, offset, threshold, separator, step, divisor, probe)
	pbt.note(t, fmt.tprintf("request=%s", request))

	target_path := os.get_env("KVIST_PBT_DATA_TRANSFORM_TARGET", t.value_allocator)
	if target_path == "" {
		return pbt.error("KVIST_PBT_DATA_TRANSFORM_TARGET is not set")
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
		return pbt.fail(fmt.tprintf("Data transform target exited with %d", process.exit_code))
	}

	parts := strings.split(process.stdout, "\t", t.value_allocator)
	field := 0
	for expected_sequence, sequence_index in expected {
		if field >= len(parts) {
			return pbt.fail(fmt.tprintf("%s result is missing", DATA_TRANSFORM_NAMES[sequence_index]))
		}
		length, length_ok := strconv.parse_int(parts[field], 10)
		field += 1
		if !length_ok || length < 0 || length > DATA_TRANSFORM_RESULT_CAPACITY {
			return pbt.fail(fmt.tprintf(
				"%s returned invalid length %q",
				DATA_TRANSFORM_NAMES[sequence_index],
				parts[field - 1],
			))
		}
		if length != expected_sequence.length {
			return pbt.fail(fmt.tprintf(
				"%s length mismatch: expected=%d actual=%d",
				DATA_TRANSFORM_NAMES[sequence_index],
				expected_sequence.length,
				length,
			))
		}
		for item_index in 0 ..< length {
			if field >= len(parts) {
				return pbt.fail(fmt.tprintf(
					"%s item %d is missing",
					DATA_TRANSFORM_NAMES[sequence_index],
					item_index,
				))
			}
			actual, ok := strconv.parse_int(parts[field], 10)
			field += 1
			if !ok || actual != expected_sequence.values[item_index] {
				return pbt.fail(fmt.tprintf(
					"%s item %d mismatch: expected=%d actual=%q",
					DATA_TRANSFORM_NAMES[sequence_index],
					item_index,
					expected_sequence.values[item_index],
					parts[field - 1],
				))
			}
		}
	}
	set_count, set_count_ok := data_transform_parse_int(parts, &field)
	if !set_count_ok || set_count != expected_set.count {
		return pbt.fail(fmt.tprintf("into-set count mismatch: expected=%d actual=%d", expected_set.count, set_count))
	}
	for value_index in 0 ..< DATA_TRANSFORM_VALUE_COUNT {
		present, present_ok := data_transform_parse_int(parts, &field)
		if !present_ok || (present != 0 && present != 1) || (present == 1) != expected_set.present[value_index] {
			return pbt.fail(fmt.tprintf("into-set membership mismatch for %d", value_index + DATA_TRANSFORM_VALUE_MIN))
		}
	}
	if field >= len(parts) {
		return pbt.fail("includes? result is missing")
	}
	actual_includes, includes_ok := strconv.parse_int(parts[field], 10)
	field += 1
	if !includes_ok || (actual_includes != 0 && actual_includes != 1) || (actual_includes == 1) != expected_includes {
		return pbt.fail(fmt.tprintf("includes? mismatch: expected=%v actual=%d", expected_includes, actual_includes))
	}
	if field >= len(parts) || parts[field] != "done" || field + 1 != len(parts) {
		return pbt.fail(fmt.tprintf("unexpected transform target trailer: %q", process.stdout))
	}
	return pbt.pass()
}

generated_transform_input :: proc(t: ^pbt.T, stats: ^Data_Transform_Input_Stats) -> Data_Transform_Sequence {
	result: Data_Transform_Sequence
	result.length = pbt.draw(t, pbt.int_range(0, DATA_TRANSFORM_INPUT_CAPACITY))
	for index in 0 ..< result.length {
		value := pbt.draw(t, pbt.int_range(DATA_TRANSFORM_VALUE_MIN, DATA_TRANSFORM_VALUE_MAX))
		for prior in 0 ..< index {
			stats.has_dupes = stats.has_dupes || result.values[prior] == value
		}
		result.values[index] = value
	}
	return result
}

data_transform_expected :: proc(input, other: Data_Transform_Sequence, n, offset, threshold, separator, step, divisor: int) -> [len(DATA_TRANSFORM_NAMES)]Data_Transform_Sequence {
	result: [len(DATA_TRANSFORM_NAMES)]Data_Transform_Sequence
	result[0] = input
	for index in 0 ..< input.length {
		data_transform_append(&result[1], input.values[index] + offset)
		data_transform_append(&result[2], input.values[index] + index)
		if input.values[index] >= threshold {
			data_transform_append(&result[3], input.values[index])
			data_transform_append(&result[15], input.values[index] + offset)
		} else {
			data_transform_append(&result[14], input.values[index])
		}
		if (index + input.values[index]) % divisor == 0 {
			data_transform_append(&result[16], input.values[index] + index + offset)
		}
		data_transform_append(&result[17], input.values[index])
		data_transform_append(&result[17], input.values[index] + offset)
	}

	middle := data_transform_clamp(n, 0, input.length)
	for index in 0 ..< middle {
		data_transform_append(&result[4], input.values[index])
		data_transform_append(&result[8], input.values[index])
	}
	for index in middle ..< input.length {
		data_transform_append(&result[5], input.values[index])
		data_transform_append(&result[9], input.values[index])
	}
	for index := input.length - 1; index >= 0; index -= 1 {
		data_transform_append(&result[6], input.values[index])
	}
	for index in 0 ..< input.length {
		if !data_transform_contains(result[7], input.values[index]) {
			data_transform_append(&result[7], input.values[index])
		}
		if index > 0 {
			data_transform_append(&result[10], separator)
		}
		data_transform_append(&result[10], input.values[index])
	}
	if step > 0 {
		for index := 0; index < input.length; index += step {
			data_transform_append(&result[11], input.values[index])
		}
	}
	result[12] = input
	result[13] = input
	for index in 0 ..< input.length {
		key := input.values[index] % divisor
		seen := false
		for prior in 0 ..< result[18].length {
			if result[18].values[prior] % divisor == key {
				seen = true
				break
			}
		}
		if !seen {
			data_transform_append(&result[18], input.values[index])
		}
	}
	interleave_length := min(input.length, other.length)
	for index in 0 ..< interleave_length {
		data_transform_append(&result[19], input.values[index])
		data_transform_append(&result[19], other.values[index])
	}
	for index in 1 ..< input.length {
		data_transform_append(&result[20], input.values[index])
	}
	for index in 0 ..< max(input.length - 1, 0) {
		data_transform_append(&result[21], input.values[index])
	}
	for index in 0 ..< input.length {
		data_transform_append(&result[22], input.values[index])
	}
	for index in 0 ..< other.length {
		data_transform_append(&result[22], other.values[index])
	}
	for index := other.length - 1; index >= 0; index -= 1 {
		data_transform_append(&result[23], other.values[index])
	}
	for index in 0 ..< input.length {
		data_transform_append(&result[23], input.values[index])
	}
	return result
}

data_transform_request :: proc(input, other: Data_Transform_Sequence, n, offset, threshold, separator, step, divisor, probe: int) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	strings.write_byte(&builder, '[')
	data_transform_write_sequence(&builder, input)
	strings.write_byte(&builder, ' ')
	data_transform_write_sequence(&builder, other)
	fmt.sbprintf(&builder, " %d %d %d %d %d %d %d]", n, offset, threshold, separator, step, divisor, probe)
	return strings.to_string(builder)
}

data_transform_write_sequence :: proc(builder: ^strings.Builder, sequence: Data_Transform_Sequence) {
	strings.write_byte(builder, '[')
	for index in 0 ..< sequence.length {
		if index > 0 {
			strings.write_byte(builder, ' ')
		}
		fmt.sbprintf(builder, "%d", sequence.values[index])
	}
	strings.write_byte(builder, ']')
}

data_transform_append :: proc(sequence: ^Data_Transform_Sequence, value: int) {
	sequence.values[sequence.length] = value
	sequence.length += 1
}

data_transform_contains :: proc(sequence: Data_Transform_Sequence, value: int) -> bool {
	for index in 0 ..< sequence.length {
		if sequence.values[index] == value {
			return true
		}
	}
	return false
}

data_transform_set_union :: proc(input, other: Data_Transform_Sequence) -> Data_Transform_Set {
	result: Data_Transform_Set
	for index in 0 ..< input.length {
		data_transform_set_add(&result, input.values[index])
	}
	for index in 0 ..< other.length {
		data_transform_set_add(&result, other.values[index])
	}
	return result
}

data_transform_set_add :: proc(result: ^Data_Transform_Set, value: int) {
	index := value - DATA_TRANSFORM_VALUE_MIN
	if !result.present[index] {
		result.present[index] = true
		result.count += 1
	}
}

data_transform_parse_int :: proc(parts: []string, field: ^int) -> (int, bool) {
	if field^ >= len(parts) {
		return 0, false
	}
	value, ok := strconv.parse_int(parts[field^], 10)
	field^ += 1
	return value, ok
}

data_transform_clamp :: proc(value, minimum, maximum: int) -> int {
	if value < minimum {
		return minimum
	}
	if value > maximum {
		return maximum
	}
	return value
}

data_transform_coverage :: proc(
	t: ^pbt.T,
	input, other: Data_Transform_Sequence,
	expected: [len(DATA_TRANSFORM_NAMES)]Data_Transform_Sequence,
	expected_set: Data_Transform_Set,
	n, offset, step: int,
	stats, other_stats: Data_Transform_Input_Stats,
	expected_includes: bool,
) {
	filtered := expected[3]
	kept := expected[15]
	pbt.cover(t, input.length == 0, 5, "empty-input")
	pbt.cover(t, stats.has_dupes, 15, "duplicate-input")
	pbt.cover(t, n < 0, 10, "negative-count")
	pbt.cover(t, n > input.length, 20, "oversized-count")
	pbt.cover(t, step <= 0, 15, "non-positive-step")
	pbt.cover(t, offset != 0, 70, "non-zero-map-offset")
	pbt.cover(t, input.length > 0 && filtered.length == 0, 5, "filter-none")
	pbt.cover(t, input.length > 0 && filtered.length == input.length, 5, "filter-all")
	pbt.cover(t, filtered.length > 0 && filtered.length < input.length, 10, "filter-some")
	pbt.cover(t, input.length > 0 && kept.length == 0, 5, "keep-none")
	pbt.cover(t, input.length > 0 && kept.length == input.length, 5, "keep-all")
	pbt.cover(t, expected[18].length < input.length, 20, "distinct-key-collision")
	pbt.cover(t, input.length != other.length, 50, "unequal-interleave-inputs")
	pbt.cover(t, expected_includes, 20, "probe-present")
	pbt.cover(t, !expected_includes, 40, "probe-missing")
	pbt.cover(t, other.length == 0, 5, "into-empty-source")
	pbt.cover(t, input.length > 0 && other.length > 0, 60, "into-nonempty-inputs")
	pbt.cover(t, expected_set.count < input.length + other.length, 25, "into-set-deduplicates")
	pbt.cover(t, other.length > 0 && data_transform_source_adds_member(input, other), 30, "into-set-adds-member")
	pbt.cover(t, other.length > 0 && !data_transform_source_adds_member(input, other), 5, "into-set-only-duplicates")
	pbt.cover(t, stats.has_dupes || other_stats.has_dupes, 30, "into-duplicate-input")
}

data_transform_source_adds_member :: proc(input, other: Data_Transform_Sequence) -> bool {
	for index in 0 ..< other.length {
		if !data_transform_contains(input, other.values[index]) {
			return true
		}
	}
	return false
}
