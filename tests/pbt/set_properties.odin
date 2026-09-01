package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

SET_VALUE_MIN :: -4
SET_VALUE_MAX :: 4
SET_DOMAIN_SIZE :: SET_VALUE_MAX - SET_VALUE_MIN + 1
SET_RESULT_NAMES := [?]string {
	"lhs input",
	"rhs input",
	"union",
	"intersection",
	"difference",
	"add",
	"remove",
	"union!",
	"intersection!",
	"difference!",
	"add!",
	"remove!",
}
SET_RESULT_COUNT :: len(SET_RESULT_NAMES)
SET_DOMAIN_MASK :: u16((1 << SET_DOMAIN_SIZE) - 1)

Set_Input_Stats :: struct {
	length:    int,
	has_dupes: bool,
}

native_set_operations_match_bitmask_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	strings.write_byte(&builder, '[')
	lhs_stats: Set_Input_Stats
	lhs := generated_set_input(t, &builder, &lhs_stats)
	strings.write_byte(&builder, ' ')
	rhs_stats: Set_Input_Stats
	rhs := generated_set_input(t, &builder, &rhs_stats)
	probe := pbt.draw(t, pbt.int_range(SET_VALUE_MIN, SET_VALUE_MAX))
	fmt.sbprintf(&builder, " %d]", probe)
	request := strings.to_string(builder)

	probe_bit := set_value_bit(probe)
	intersection := lhs & rhs
	set_pbt_coverage(t, lhs, rhs, probe_bit, lhs_stats, rhs_stats)
	pbt.note(t, fmt.tprintf("request=%s lhs-mask=%d rhs-mask=%d", request, lhs, rhs))

	target_path := os.get_env("KVIST_PBT_SET_TARGET", t.value_allocator)
	if target_path == "" {
		return pbt.error("KVIST_PBT_SET_TARGET is not set")
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
		return pbt.fail(fmt.tprintf("set target exited with %d", process.exit_code))
	}

	expected := [SET_RESULT_COUNT]u16 {
		lhs,
		rhs,
		lhs | rhs,
		intersection,
		lhs & (~rhs) & SET_DOMAIN_MASK,
		lhs | probe_bit,
		lhs & (~probe_bit) & SET_DOMAIN_MASK,
		lhs | rhs,
		intersection,
		lhs & (~rhs) & SET_DOMAIN_MASK,
		lhs | probe_bit,
		lhs & (~probe_bit) & SET_DOMAIN_MASK,
	}
	fields_per_set := SET_DOMAIN_SIZE + 1
	expected_field_count := SET_RESULT_COUNT * fields_per_set + 3
	parts := strings.split(process.stdout, "\t", t.value_allocator)
	if len(parts) != expected_field_count {
		return pbt.fail(fmt.tprintf(
			"set target returned %d fields, expected %d: %q",
			len(parts),
			expected_field_count,
			process.stdout,
		))
	}

	field := 0
	for result_index in 0 ..< SET_RESULT_COUNT {
		count, count_ok := strconv.parse_int(parts[field], 10)
		field += 1
		if !count_ok {
			return pbt.fail(fmt.tprintf("%s returned invalid count", SET_RESULT_NAMES[result_index]))
		}
		actual: u16
		for bit_index in 0 ..< SET_DOMAIN_SIZE {
			present, present_ok := strconv.parse_int(parts[field], 10)
			field += 1
			if !present_ok || (present != 0 && present != 1) {
				return pbt.fail(fmt.tprintf(
					"%s returned invalid membership bit %d",
					SET_RESULT_NAMES[result_index],
					bit_index,
				))
			}
			if present == 1 {
				actual |= u16(1) << u64(bit_index)
			}
		}
		if actual != expected[result_index] || count != set_mask_count(expected[result_index]) {
			return pbt.fail(fmt.tprintf(
				"%s mismatch: expected-mask=%d expected-count=%d actual-mask=%d actual-count=%d",
				SET_RESULT_NAMES[result_index],
				expected[result_index],
				set_mask_count(expected[result_index]),
				actual,
				count,
			))
		}
	}

	expected_relations := [3]bool {
		lhs & rhs == lhs,
		lhs & rhs == rhs,
		intersection == 0,
	}
	for relation, relation_index in expected_relations {
		actual, ok := strconv.parse_int(parts[field + relation_index], 10)
		if !ok || (actual != 0 && actual != 1) || (actual == 1) != relation {
			return pbt.fail(fmt.tprintf(
				"set relation %d mismatch: expected=%v actual=%q",
				relation_index,
				relation,
				parts[field + relation_index],
			))
		}
	}
	return pbt.pass()
}

generated_set_input :: proc(t: ^pbt.T, builder: ^strings.Builder, stats: ^Set_Input_Stats) -> u16 {
	strings.write_byte(builder, '[')
	length := pbt.draw(t, pbt.int_range(0, 10))
	stats.length = length
	mask: u16
	for index in 0 ..< length {
		value := pbt.draw(t, pbt.int_range(SET_VALUE_MIN, SET_VALUE_MAX))
		bit := set_value_bit(value)
		stats.has_dupes = stats.has_dupes || mask & bit != 0
		mask |= bit
		if index > 0 {
			strings.write_byte(builder, ' ')
		}
		fmt.sbprintf(builder, "%d", value)
	}
	strings.write_byte(builder, ']')
	return mask
}

set_value_bit :: proc(value: int) -> u16 {
	return u16(1) << u64(value - SET_VALUE_MIN)
}

set_mask_count :: proc(mask: u16) -> int {
	count := 0
	remaining := mask
	for remaining != 0 {
		count += int(remaining & 1)
		remaining >>= 1
	}
	return count
}

set_pbt_coverage :: proc(t: ^pbt.T, lhs, rhs, probe_bit: u16, lhs_stats, rhs_stats: Set_Input_Stats) {
	intersection := lhs & rhs
	pbt.cover(t, lhs_stats.has_dupes || rhs_stats.has_dupes, 25, "duplicate-input")
	pbt.cover(t, intersection != 0, 25, "overlapping-inputs")
	pbt.cover(t, intersection == 0, 8, "disjoint-inputs")
	pbt.cover(t, lhs & rhs == lhs || lhs & rhs == rhs, 8, "subset-inputs")
	pbt.cover(t, lhs_stats.length == 0 || rhs_stats.length == 0, 8, "empty-input")
	pbt.cover(t, lhs & probe_bit != 0, 20, "probe-present")
	pbt.cover(t, lhs & probe_bit == 0, 20, "probe-missing")
}
