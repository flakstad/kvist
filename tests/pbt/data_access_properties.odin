// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

DATA_ACCESS_CAPACITY :: 6
DATA_ACCESS_OBSERVATION_COUNT :: 31

Data_Access_Kind :: enum {
	Nil,
	Bool,
	Int,
	Float,
	String,
	Symbol,
	Keyword,
	List,
	Vector,
	Map,
	Set,
	Tagged,
}

DATA_ACCESS_KIND_NAMES := [?]string {
	"nil",
	"bool",
	"int",
	"float",
	"string",
	"symbol",
	"keyword",
	"list",
	"vector",
	"map",
	"set",
	"tagged",
}

Data_Access_Input :: struct {
	kind:   Data_Access_Kind,
	length: int,
	values: [DATA_ACCESS_CAPACITY]int,
	whole:  int,
	fraction: int,
}

data_accessors_match_shallow_model :: proc(t: ^pbt.T) -> pbt.Result {
	input := generated_data_access_input(t)
	request := data_access_request(input)
	expected := data_access_expected(input)
	pbt.note(t, fmt.tprintf("request=%s", request))
	for kind, kind_index in DATA_ACCESS_KIND_NAMES {
		pbt.cover(t, int(input.kind) == kind_index, 5, kind)
	}

	target_path := os.get_env("KVIST_PBT_DATA_ACCESS_TARGET", t.value_allocator)
	if target_path == "" {
		return pbt.error("KVIST_PBT_DATA_ACCESS_TARGET is not set")
	}
	command := [?]string{target_path}
	process := pbt.process_run_with_options(t, command[:], {
		stdin = request,
		timeout_ms = 1_000,
		max_output_bytes = 16_384,
	})
	if !process.success {
		if process.stderr != "" {
			return pbt.fail(process.stderr)
		}
		if process.error != "" {
			return pbt.fail(process.error)
		}
		return pbt.fail(fmt.tprintf("Data access target exited with %d", process.exit_code))
	}

	parts := strings.split(process.stdout, "\t", t.value_allocator)
	if len(parts) != DATA_ACCESS_OBSERVATION_COUNT + 2 {
		return pbt.fail(fmt.tprintf("Data access target returned %d fields, expected %d", len(parts), DATA_ACCESS_OBSERVATION_COUNT + 2))
	}
	expected_kind := fmt.tprintf(":%s", DATA_ACCESS_KIND_NAMES[input.kind])
	if parts[0] != expected_kind {
		return pbt.fail(fmt.tprintf("kind mismatch: expected=%s actual=%s", expected_kind, parts[0]))
	}
	for expected_value, index in expected {
		actual, ok := strconv.parse_int(parts[index + 1], 10)
		if !ok || actual != expected_value {
			return pbt.fail(fmt.tprintf(
				"Data access observation %d mismatch for %s: expected=%d actual=%q",
				index,
				DATA_ACCESS_KIND_NAMES[input.kind],
				expected_value,
				parts[index + 1],
			))
		}
	}
	if parts[len(parts) - 1] != "done" {
		return pbt.fail(fmt.tprintf("unexpected Data access trailer: %q", process.stdout))
	}
	return pbt.pass()
}

generated_data_access_input :: proc(t: ^pbt.T) -> Data_Access_Input {
	result := Data_Access_Input {
		kind = Data_Access_Kind(pbt.draw(t, pbt.int_range(0, len(DATA_ACCESS_KIND_NAMES) - 1))),
		whole = pbt.draw(t, pbt.int_range(-100, 100)),
		fraction = pbt.draw(t, pbt.int_range(1, 999)),
	}
	if result.kind == .Bool {
		result.values[0] = pbt.draw(t, pbt.int_range(0, 1))
	} else if result.kind == .Int || result.kind == .Tagged {
		result.values[0] = pbt.draw(t, pbt.int_range(-10_000, 10_000))
	} else if result.kind == .List || result.kind == .Vector || result.kind == .Map || result.kind == .Set {
		result.length = pbt.draw(t, pbt.int_range(0, DATA_ACCESS_CAPACITY))
		for index in 0 ..< result.length {
			result.values[index] = pbt.draw(t, pbt.int_range(-5, 5))
		}
	}
	return result
}

data_access_expected :: proc(input: Data_Access_Input) -> [DATA_ACCESS_OBSERVATION_COUNT]int {
	result: [DATA_ACCESS_OBSERVATION_COUNT]int
	result[int(input.kind)] = 1
	switch input.kind {
	case .String:
		result[12] = 4
	case .List, .Vector, .Map:
		result[12] = input.length
	case .Set:
		result[12] = data_access_unique_count(input)
	case .Nil, .Bool, .Int, .Float, .Symbol, .Keyword, .Tagged:
		result[12] = -1
	}
	result[13] = 1
	result[14] = 1
	result[15] = input.kind == .Int ? 1 : 0
	result[16] = input.kind == .Float ? 1 : 0
	result[17] = input.kind == .Bool ? 1 : 0
	result[18] = 1
	result[19] = 1
	result[20] = 1
	if input.kind == .List || input.kind == .Vector {
		if input.length > 0 {
			result[21] = 1
			result[22] = input.values[0]
			result[25] = 1
			result[26] = input.values[input.length - 1]
		}
		if input.length > 1 {
			result[23] = 1
			result[24] = input.values[1]
		}
	}
	if input.kind == .Map {
		for index in 0 ..< input.length {
			result[27] += index
			result[28] += input.values[index]
		}
	}
	if input.kind == .Tagged {
		result[29] = 1
		result[30] = input.values[0]
	}
	return result
}

data_access_unique_count :: proc(input: Data_Access_Input) -> int {
	count := 0
	for index in 0 ..< input.length {
		seen := false
		for prior in 0 ..< index {
			seen = seen || input.values[prior] == input.values[index]
		}
		if !seen {
			count += 1
		}
	}
	return count
}

data_access_request :: proc(input: Data_Access_Input) -> string {
	switch input.kind {
	case .Nil:
		return "nil"
	case .Bool:
		return input.values[0] == 1 ? "true" : "false"
	case .Int:
		return fmt.tprintf("%d", input.values[0])
	case .Float:
		return fmt.tprintf("%d.%03d", input.whole, input.fraction)
	case .String:
		return `"text"`
	case .Symbol:
		return "symbol"
	case .Keyword:
		return ":keyword"
	case .List:
		return data_access_sequence_request(input, '(', ')')
	case .Vector:
		return data_access_sequence_request(input, '[', ']')
	case .Map:
		builder: strings.Builder
		strings.builder_init(&builder, context.temp_allocator)
		strings.write_byte(&builder, '{')
		for index in 0 ..< input.length {
			if index > 0 {
				strings.write_byte(&builder, ' ')
			}
			fmt.sbprintf(&builder, "%d %d", index, input.values[index])
		}
		strings.write_byte(&builder, '}')
		return strings.to_string(builder)
	case .Set:
		builder: strings.Builder
		strings.builder_init(&builder, context.temp_allocator)
		strings.write_string(&builder, "#{")
		data_access_write_values(&builder, input)
		strings.write_byte(&builder, '}')
		return strings.to_string(builder)
	case .Tagged:
		return fmt.tprintf("#tag %d", input.values[0])
	}
	return "nil"
}

data_access_sequence_request :: proc(input: Data_Access_Input, open, close: rune) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	strings.write_rune(&builder, open)
	data_access_write_values(&builder, input)
	strings.write_rune(&builder, close)
	return strings.to_string(builder)
}

data_access_write_values :: proc(builder: ^strings.Builder, input: Data_Access_Input) {
	for index in 0 ..< input.length {
		if index > 0 {
			strings.write_byte(builder, ' ')
		}
		fmt.sbprintf(builder, "%d", input.values[index])
	}
}
