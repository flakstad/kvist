package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

DATA_SCAN_CAPACITY :: 10

Data_Scan_Sequence :: struct {
	length: int,
	values: [DATA_SCAN_CAPACITY]int,
}

Data_Scan_Partitions :: struct {
	count:  int,
	lengths: [DATA_SCAN_CAPACITY]int,
	values: [DATA_SCAN_CAPACITY * DATA_SCAN_CAPACITY]int,
}

Data_Scan_Model :: struct {
	find_present:         bool,
	find_value:           int,
	indexed_present:      bool,
	indexed_index:        int,
	indexed_value:        int,
	min_present:          bool,
	min_value:            int,
	max_present:          bool,
	max_value:            int,
	some:                 bool,
	every:                bool,
	not_any:              bool,
	not_every:            bool,
	take_while:           Data_Scan_Sequence,
	drop_while:           Data_Scan_Sequence,
	sorted_abs:           Data_Scan_Sequence,
	sorted_desc:          Data_Scan_Sequence,
	partitioned:          Data_Scan_Partitions,
	partitioned_all:      Data_Scan_Partitions,
	partitioned_by:       Data_Scan_Partitions,
}

Data_Scan_Stats :: struct {
	has_abs_tie: bool,
}

data_scans_and_partitions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	stats: Data_Scan_Stats
	input := generated_scan_input(t, &stats)
	threshold := pbt.draw(t, pbt.int_range(-5, 5))
	indexed_start := pbt.draw(t, pbt.int_range(-1, input.length + 1))
	partition_size := pbt.draw(t, pbt.int_range(-1, 5))
	divisor := pbt.draw(t, pbt.int_range(1, 3))
	expected := data_scan_model(input, threshold, indexed_start, partition_size, divisor)
	data_scan_coverage(t, input, expected, partition_size, stats)
	request := data_scan_request(input, threshold, indexed_start, partition_size, divisor)
	pbt.note(t, fmt.tprintf("request=%s", request))

	target_path := os.get_env("KVIST_PBT_DATA_SCAN_TARGET", t.value_allocator)
	if target_path == "" {
		return pbt.error("KVIST_PBT_DATA_SCAN_TARGET is not set")
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
		return pbt.fail(fmt.tprintf("Data scan target exited with %d", process.exit_code))
	}

	parts := strings.split(process.stdout, "\t", t.value_allocator)
	field := 0
	if result := parse_data_scan_optional(parts, &field, expected.find_present, expected.find_value, "find"); result.status != .Pass {
		return result
	}
	if result := parse_data_scan_indexed(parts, &field, expected); result.status != .Pass {
		return result
	}
	if result := parse_data_scan_optional(parts, &field, expected.min_present, expected.min_value, "min-by"); result.status != .Pass {
		return result
	}
	if result := parse_data_scan_optional(parts, &field, expected.max_present, expected.max_value, "max-by"); result.status != .Pass {
		return result
	}
	booleans := [?]bool{expected.some, expected.every, expected.not_any, expected.not_every}
	boolean_names := [?]string{"some?", "every?", "not-any?", "not-every?"}
	for expected_boolean, boolean_index in booleans {
		actual, ok := parse_data_scan_int(parts, &field)
		if !ok || (actual != 0 && actual != 1) || (actual == 1) != expected_boolean {
			return pbt.fail(fmt.tprintf("%s mismatch", boolean_names[boolean_index]))
		}
	}

	sequences := [?]Data_Scan_Sequence {
		expected.take_while,
		expected.drop_while,
		expected.sorted_abs,
		expected.sorted_desc,
	}
	sequence_names := [?]string{"take-while", "drop-while", "sort-by", "sort-with"}
	for sequence, sequence_index in sequences {
		if result := parse_data_scan_sequence(parts, &field, sequence, sequence_names[sequence_index]); result.status != .Pass {
			return result
		}
	}

	partitions := [?]Data_Scan_Partitions {
		expected.partitioned,
		expected.partitioned_all,
		expected.partitioned_by,
	}
	partition_names := [?]string{"partition", "partition-all", "partition-by"}
	for partition, partition_index in partitions {
		if result := parse_data_scan_partitions(parts, &field, partition, partition_names[partition_index]); result.status != .Pass {
			return result
		}
	}
	if field >= len(parts) || parts[field] != "done" || field + 1 != len(parts) {
		return pbt.fail(fmt.tprintf("unexpected scan target trailer: %q", process.stdout))
	}
	return pbt.pass()
}

generated_scan_input :: proc(t: ^pbt.T, stats: ^Data_Scan_Stats) -> Data_Scan_Sequence {
	result: Data_Scan_Sequence
	result.length = pbt.draw(t, pbt.int_range(0, DATA_SCAN_CAPACITY))
	for index in 0 ..< result.length {
		value := pbt.draw(t, pbt.int_range(-5, 5))
		for prior in 0 ..< index {
			stats.has_abs_tie = stats.has_abs_tie ||
				data_scan_abs(result.values[prior]) == data_scan_abs(value) && result.values[prior] != value
		}
		result.values[index] = value
	}
	return result
}

data_scan_model :: proc(input: Data_Scan_Sequence, threshold, indexed_start, partition_size, divisor: int) -> Data_Scan_Model {
	result := Data_Scan_Model{every = true, not_any = true}
	for index in 0 ..< input.length {
		value := input.values[index]
		matches := value >= threshold
		if matches && !result.find_present {
			result.find_present = true
			result.find_value = value
		}
		if matches && index >= indexed_start && !result.indexed_present {
			result.indexed_present = true
			result.indexed_index = index
			result.indexed_value = value
		}
		result.some = result.some || matches
		result.every = result.every && matches
		result.not_any = result.not_any && !matches
		result.not_every = result.not_every || !matches
		if index == 0 || data_scan_abs(value) < data_scan_abs(result.min_value) {
			result.min_present = true
			result.min_value = value
		}
		if index == 0 || data_scan_abs(value) > data_scan_abs(result.max_value) {
			result.max_present = true
			result.max_value = value
		}
	}

	prefix := 0
	for prefix < input.length && input.values[prefix] >= threshold {
		prefix += 1
	}
	for index in 0 ..< prefix {
		data_scan_append(&result.take_while, input.values[index])
	}
	for index in prefix ..< input.length {
		data_scan_append(&result.drop_while, input.values[index])
	}
	result.sorted_abs = input
	result.sorted_desc = input
	data_scan_stable_sort_abs(&result.sorted_abs)
	data_scan_stable_sort_desc(&result.sorted_desc)
	result.partitioned = data_scan_partition(input, partition_size, false)
	result.partitioned_all = data_scan_partition(input, partition_size, true)
	result.partitioned_by = data_scan_partition_by(input, divisor)
	return result
}

data_scan_stable_sort_abs :: proc(sequence: ^Data_Scan_Sequence) {
	for index in 1 ..< sequence.length {
		value := sequence.values[index]
		target := index
		for target > 0 && data_scan_abs(value) < data_scan_abs(sequence.values[target - 1]) {
			sequence.values[target] = sequence.values[target - 1]
			target -= 1
		}
		sequence.values[target] = value
	}
}

data_scan_stable_sort_desc :: proc(sequence: ^Data_Scan_Sequence) {
	for index in 1 ..< sequence.length {
		value := sequence.values[index]
		target := index
		for target > 0 && value > sequence.values[target - 1] {
			sequence.values[target] = sequence.values[target - 1]
			target -= 1
		}
		sequence.values[target] = value
	}
}

data_scan_partition :: proc(input: Data_Scan_Sequence, size: int, include_trailing: bool) -> Data_Scan_Partitions {
	result: Data_Scan_Partitions
	if size <= 0 {
		return result
	}
	start := 0
	for start < input.length {
		remaining := input.length - start
		length := size
		if remaining < size {
			if !include_trailing {
				break
			}
			length = remaining
		}
		data_scan_add_partition(&result, input, start, length)
		start += size
	}
	return result
}

data_scan_partition_by :: proc(input: Data_Scan_Sequence, divisor: int) -> Data_Scan_Partitions {
	result: Data_Scan_Partitions
	if input.length == 0 {
		return result
	}
	start := 0
	for index in 1 ..< input.length {
		if input.values[index] % divisor != input.values[index - 1] % divisor {
			data_scan_add_partition(&result, input, start, index - start)
			start = index
		}
	}
	data_scan_add_partition(&result, input, start, input.length - start)
	return result
}

data_scan_add_partition :: proc(result: ^Data_Scan_Partitions, input: Data_Scan_Sequence, start, length: int) {
	group := result.count
	result.lengths[group] = length
	for index in 0 ..< length {
		result.values[group * DATA_SCAN_CAPACITY + index] = input.values[start + index]
	}
	result.count += 1
}

data_scan_request :: proc(input: Data_Scan_Sequence, threshold, indexed_start, partition_size, divisor: int) -> string {
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
	fmt.sbprintf(&builder, " %d %d %d %d]", threshold, indexed_start, partition_size, divisor)
	return strings.to_string(builder)
}

data_scan_append :: proc(sequence: ^Data_Scan_Sequence, value: int) {
	sequence.values[sequence.length] = value
	sequence.length += 1
}

data_scan_abs :: proc(value: int) -> int {
	if value < 0 {
		return -value
	}
	return value
}

parse_data_scan_optional :: proc(parts: []string, field: ^int, expected_present: bool, expected_value: int, name: string) -> pbt.Result {
	present, present_ok := parse_data_scan_int(parts, field)
	value, value_ok := parse_data_scan_int(parts, field)
	if !present_ok || !value_ok || (present != 0 && present != 1) ||
	   (present == 1) != expected_present || (expected_present && value != expected_value) {
		return pbt.fail(fmt.tprintf("%s mismatch: expected-present=%v expected-value=%d", name, expected_present, expected_value))
	}
	return pbt.pass()
}

parse_data_scan_indexed :: proc(parts: []string, field: ^int, expected: Data_Scan_Model) -> pbt.Result {
	present, present_ok := parse_data_scan_int(parts, field)
	index, index_ok := parse_data_scan_int(parts, field)
	value, value_ok := parse_data_scan_int(parts, field)
	if !present_ok || !index_ok || !value_ok || (present != 0 && present != 1) ||
	   (present == 1) != expected.indexed_present ||
	   (expected.indexed_present && (index != expected.indexed_index || value != expected.indexed_value)) {
		return pbt.fail(fmt.tprintf(
			"find-indexed mismatch: expected-present=%v expected-index=%d expected-value=%d",
			expected.indexed_present,
			expected.indexed_index,
			expected.indexed_value,
		))
	}
	return pbt.pass()
}

parse_data_scan_sequence :: proc(parts: []string, field: ^int, expected: Data_Scan_Sequence, name: string) -> pbt.Result {
	length, length_ok := parse_data_scan_int(parts, field)
	if !length_ok || length != expected.length {
		return pbt.fail(fmt.tprintf("%s length mismatch: expected=%d actual=%d", name, expected.length, length))
	}
	for index in 0 ..< length {
		actual, ok := parse_data_scan_int(parts, field)
		if !ok || actual != expected.values[index] {
			return pbt.fail(fmt.tprintf("%s item %d mismatch: expected=%d actual=%d", name, index, expected.values[index], actual))
		}
	}
	return pbt.pass()
}

parse_data_scan_partitions :: proc(parts: []string, field: ^int, expected: Data_Scan_Partitions, name: string) -> pbt.Result {
	count, count_ok := parse_data_scan_int(parts, field)
	if !count_ok || count != expected.count {
		return pbt.fail(fmt.tprintf("%s count mismatch: expected=%d actual=%d", name, expected.count, count))
	}
	for group in 0 ..< count {
		length, length_ok := parse_data_scan_int(parts, field)
		if !length_ok || length != expected.lengths[group] {
			return pbt.fail(fmt.tprintf("%s group %d length mismatch", name, group))
		}
		for index in 0 ..< length {
			actual, ok := parse_data_scan_int(parts, field)
			expected_value := expected.values[group * DATA_SCAN_CAPACITY + index]
			if !ok || actual != expected_value {
				return pbt.fail(fmt.tprintf("%s group %d item %d mismatch", name, group, index))
			}
		}
	}
	return pbt.pass()
}

parse_data_scan_int :: proc(parts: []string, field: ^int) -> (int, bool) {
	if field^ >= len(parts) {
		return 0, false
	}
	value, ok := strconv.parse_int(parts[field^], 10)
	field^ += 1
	return value, ok
}

data_scan_coverage :: proc(t: ^pbt.T, input: Data_Scan_Sequence, expected: Data_Scan_Model, partition_size: int, stats: Data_Scan_Stats) {
	pbt.cover(t, input.length == 0, 5, "empty-input")
	pbt.cover(t, expected.find_present, 30, "find-hit")
	pbt.cover(t, !expected.find_present, 10, "find-miss")
	pbt.cover(t, expected.indexed_present, 20, "find-indexed-hit")
	pbt.cover(t, !expected.indexed_present, 15, "find-indexed-miss")
	pbt.cover(t, stats.has_abs_tie, 10, "stable-sort-tie")
	pbt.cover(t, partition_size <= 0, 20, "non-positive-partition")
	pbt.cover(t, partition_size > 0 && input.length % partition_size != 0, 20, "trailing-partition")
	pbt.cover(t, expected.partitioned_by.count > 1, 25, "partition-by-boundary")
}
