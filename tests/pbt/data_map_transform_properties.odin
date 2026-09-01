package main

import "core:fmt"
import "core:os"
import "core:strings"

import pbt "pbt:pbt"

DATA_MAP_TRANSFORM_CAPACITY :: 8
DATA_MAP_TRANSFORM_NAMES := [?]string {
	"select-keys",
	"merge",
	"merge-with",
	"update-keys",
	"update-vals",
	"map-entries",
	"filter-entries",
	"into",
	"entries-roundtrip",
	"keys-vals-roundtrip",
}

Data_Map_Transform_Keys :: struct {
	length: int,
	values: [DATA_MAP_TRANSFORM_CAPACITY]int,
}

Data_Map_Transform_Entries :: struct {
	length: int,
	keys:   [DATA_MAP_TRANSFORM_CAPACITY]int,
	values: [DATA_MAP_TRANSFORM_CAPACITY]int,
}

Data_Map_Transform_Stats :: struct {
	lhs_count:        int,
	rhs_count:        int,
	selected_present: bool,
	selected_missing: bool,
	source_duplicate: bool,
	source_overwrite: bool,
}

data_map_transforms_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	stats: Data_Map_Transform_Stats
	lhs := generated_data_transform_map(t, &stats.lhs_count)
	rhs := generated_data_transform_map(t, &stats.rhs_count)
	selected := generated_data_transform_keys(t)
	source := generated_data_transform_entries(t, lhs, &stats)
	divisor := pbt.draw(t, pbt.int_range(1, 3))
	offset := pbt.draw(t, pbt.int_range(-3, 3))
	threshold := pbt.draw(t, pbt.int_range(MAP_VALUE_MIN, MAP_VALUE_MAX))
	expected := data_map_transform_expected(lhs, rhs, selected, source, divisor, offset, threshold)
	data_map_transform_selection_stats(lhs, selected, &stats)
	data_map_transform_coverage(t, lhs, rhs, expected, threshold, stats)
	request := data_map_transform_request(lhs, rhs, selected, source, divisor, offset, threshold)
	pbt.note(t, fmt.tprintf("request=%s", request))

	target_path := os.get_env("KVIST_PBT_DATA_MAP_TRANSFORM_TARGET", t.value_allocator)
	if target_path == "" {
		return pbt.error("KVIST_PBT_DATA_MAP_TRANSFORM_TARGET is not set")
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
		return pbt.fail(fmt.tprintf("Data map transform target exited with %d", process.exit_code))
	}

	parts := strings.split(process.stdout, "\t", t.value_allocator)
	field := 0
	for expected_map, result_index in expected {
		result := parse_native_map_result(parts, &field, expected_map, DATA_MAP_TRANSFORM_NAMES[result_index])
		if result.status != .Pass {
			return result
		}
	}
	if field >= len(parts) || parts[field] != "done" || field + 1 != len(parts) {
		return pbt.fail(fmt.tprintf("unexpected Data map transform trailer: %q", process.stdout))
	}
	return pbt.pass()
}

generated_data_transform_map :: proc(t: ^pbt.T, count: ^int) -> Native_Map_Model {
	result: Native_Map_Model
	for key_index in 0 ..< MAP_KEY_COUNT {
		if pbt.draw(t, pbt.boolean()) {
			result.present[key_index] = true
			result.values[key_index] = pbt.draw(t, pbt.int_range(MAP_VALUE_MIN, MAP_VALUE_MAX))
			count^ += 1
		}
	}
	return result
}

generated_data_transform_keys :: proc(t: ^pbt.T) -> Data_Map_Transform_Keys {
	result: Data_Map_Transform_Keys
	result.length = pbt.draw(t, pbt.int_range(0, DATA_MAP_TRANSFORM_CAPACITY))
	for index in 0 ..< result.length {
		result.values[index] = pbt.draw(t, pbt.int_range(MAP_KEY_MIN - 1, MAP_KEY_MAX + 1))
	}
	return result
}

generated_data_transform_entries :: proc(t: ^pbt.T, lhs: Native_Map_Model, stats: ^Data_Map_Transform_Stats) -> Data_Map_Transform_Entries {
	result: Data_Map_Transform_Entries
	result.length = pbt.draw(t, pbt.int_range(0, DATA_MAP_TRANSFORM_CAPACITY))
	seen: [MAP_KEY_COUNT]bool
	for index in 0 ..< result.length {
		key := pbt.draw(t, pbt.int_range(MAP_KEY_MIN, MAP_KEY_MAX))
		key_index := native_map_key_index(key)
		result.keys[index] = key
		result.values[index] = pbt.draw(t, pbt.int_range(MAP_VALUE_MIN, MAP_VALUE_MAX))
		stats.source_duplicate = stats.source_duplicate || seen[key_index]
		stats.source_overwrite = stats.source_overwrite || lhs.present[key_index]
		seen[key_index] = true
	}
	return result
}

data_map_transform_expected :: proc(
	lhs, rhs: Native_Map_Model,
	selected: Data_Map_Transform_Keys,
	source: Data_Map_Transform_Entries,
	divisor, offset, threshold: int,
) -> [len(DATA_MAP_TRANSFORM_NAMES)]Native_Map_Model {
	result: [len(DATA_MAP_TRANSFORM_NAMES)]Native_Map_Model
	for index in 0 ..< selected.length {
		key := selected.values[index]
		if key >= MAP_KEY_MIN && key <= MAP_KEY_MAX {
			key_index := native_map_key_index(key)
			if lhs.present[key_index] {
				result[0] = native_map_assoc(result[0], key, lhs.values[key_index])
			}
		}
	}
	result[1] = native_map_merge(lhs, rhs)
	result[2] = lhs
	for key_index in 0 ..< MAP_KEY_COUNT {
		key := key_index + MAP_KEY_MIN
		if rhs.present[key_index] {
			value := rhs.values[key_index]
			if lhs.present[key_index] {
				value += lhs.values[key_index]
			}
			result[2] = native_map_assoc(result[2], key, value)
		}
		if lhs.present[key_index] {
			value := lhs.values[key_index]
			result[3] = native_map_assoc(result[3], key % divisor, value)
			result[4] = native_map_assoc(result[4], key, value + offset)
			result[5] = native_map_assoc(result[5], key % divisor, value + key)
			if value >= threshold {
				result[6] = native_map_assoc(result[6], key, value)
			}
		}
	}
	result[7] = lhs
	for index in 0 ..< source.length {
		result[7] = native_map_assoc(result[7], source.keys[index], source.values[index])
	}
	result[8] = result[7]
	result[9] = result[7]
	return result
}

data_map_transform_request :: proc(
	lhs, rhs: Native_Map_Model,
	selected: Data_Map_Transform_Keys,
	source: Data_Map_Transform_Entries,
	divisor, offset, threshold: int,
) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	strings.write_byte(&builder, '[')
	data_map_transform_write_map(&builder, lhs)
	strings.write_byte(&builder, ' ')
	data_map_transform_write_map(&builder, rhs)
	strings.write_byte(&builder, ' ')
	data_map_transform_write_keys(&builder, selected)
	strings.write_byte(&builder, ' ')
	data_map_transform_write_entries(&builder, source)
	fmt.sbprintf(&builder, " %d %d %d]", divisor, offset, threshold)
	return strings.to_string(builder)
}

data_map_transform_write_map :: proc(builder: ^strings.Builder, model: Native_Map_Model) {
	strings.write_byte(builder, '{')
	written := 0
	for key_index in 0 ..< MAP_KEY_COUNT {
		if model.present[key_index] {
			if written > 0 {
				strings.write_byte(builder, ' ')
			}
			fmt.sbprintf(builder, "%d %d", key_index + MAP_KEY_MIN, model.values[key_index])
			written += 1
		}
	}
	strings.write_byte(builder, '}')
}

data_map_transform_write_keys :: proc(builder: ^strings.Builder, keys: Data_Map_Transform_Keys) {
	strings.write_byte(builder, '[')
	for index in 0 ..< keys.length {
		if index > 0 {
			strings.write_byte(builder, ' ')
		}
		fmt.sbprintf(builder, "%d", keys.values[index])
	}
	strings.write_byte(builder, ']')
}

data_map_transform_write_entries :: proc(builder: ^strings.Builder, entries: Data_Map_Transform_Entries) {
	strings.write_byte(builder, '[')
	for index in 0 ..< entries.length {
		if index > 0 {
			strings.write_byte(builder, ' ')
		}
		fmt.sbprintf(builder, "[%d %d]", entries.keys[index], entries.values[index])
	}
	strings.write_byte(builder, ']')
}

data_map_transform_selection_stats :: proc(lhs: Native_Map_Model, selected: Data_Map_Transform_Keys, stats: ^Data_Map_Transform_Stats) {
	for index in 0 ..< selected.length {
		key := selected.values[index]
		present := key >= MAP_KEY_MIN && key <= MAP_KEY_MAX && lhs.present[native_map_key_index(key)]
		stats.selected_present = stats.selected_present || present
		stats.selected_missing = stats.selected_missing || !present
	}
}

data_map_transform_coverage :: proc(
	t: ^pbt.T,
	lhs, rhs: Native_Map_Model,
	expected: [len(DATA_MAP_TRANSFORM_NAMES)]Native_Map_Model,
	threshold: int,
	stats: Data_Map_Transform_Stats,
) {
	overlap := false
	for key_index in 0 ..< MAP_KEY_COUNT {
		overlap = overlap || lhs.present[key_index] && rhs.present[key_index]
	}
	pbt.cover(t, stats.lhs_count == 0 || stats.rhs_count == 0, 5, "empty-map-input")
	pbt.cover(t, overlap, 30, "merge-overlap")
	pbt.cover(t, stats.selected_present, 30, "selected-present-key")
	pbt.cover(t, stats.selected_missing, 30, "selected-missing-key")
	pbt.cover(t, native_map_count(expected[3]) < stats.lhs_count, 25, "updated-key-collision")
	pbt.cover(t, stats.source_duplicate, 25, "duplicate-source-key")
	pbt.cover(t, stats.source_overwrite, 30, "source-overwrites-target")
	pbt.cover(t, stats.lhs_count > 0 && native_map_count(expected[6]) == 0, 5, "filter-entries-none")
	pbt.cover(t, stats.lhs_count > 0 && native_map_count(expected[6]) == stats.lhs_count, 5, "filter-entries-all")
	pbt.cover(t, threshold != 0, 80, "non-zero-filter-threshold")
}
