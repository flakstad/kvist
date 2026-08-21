// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Data_Destructure_Stats :: struct {
	map_keys:          int,
	explicit_entry:    int,
	default_missing:   int,
	nil_present:       int,
	namespaced_keys:   int,
	string_symbol_keys: int,
	sequence_position: int,
	missing_position:  int,
	wrong_kind:        int,
	rest_binding:      int,
	as_binding:        int,
	nested_binding:    int,
	for_sequence:      int,
	for_indexed:       int,
	for_map:           int,
	nil_source:        int,
}

generated_compiler_data_destructuring_matches_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Data_Destructure_Stats
	expected := write_compiler_data_destructure_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.map_keys > 0, 3, "map-keys")
	pbt.cover(t, stats.explicit_entry > 0, 3, "explicit-entry")
	pbt.cover(t, stats.default_missing > 0, 3, "default-missing")
	pbt.cover(t, stats.nil_present > 0, 3, "nil-present")
	pbt.cover(t, stats.namespaced_keys > 0, 3, "namespaced-keys")
	pbt.cover(t, stats.string_symbol_keys > 0, 3, "string-symbol-keys")
	pbt.cover(t, stats.sequence_position > 0, 3, "sequence-position")
	pbt.cover(t, stats.missing_position > 0, 3, "missing-position")
	pbt.cover(t, stats.wrong_kind > 0, 3, "wrong-kind")
	pbt.cover(t, stats.rest_binding > 0, 3, "rest-binding")
	pbt.cover(t, stats.as_binding > 0, 3, "as-binding")
	pbt.cover(t, stats.nested_binding > 0, 3, "nested-binding")
	pbt.cover(t, stats.for_sequence > 0, 3, "for-sequence")
	pbt.cover(t, stats.for_indexed > 0, 3, "for-indexed")
	pbt.cover(t, stats.for_map > 0, 3, "for-map")
	pbt.cover(t, stats.nil_source > 0, 3, "nil-source")

	compiler_path := os.get_env("KVIST_PBT_COMPILER", t.value_allocator)
	if compiler_path == "" {
		return pbt.error("KVIST_PBT_COMPILER is not set")
	}
	source_path := os.get_env("KVIST_PBT_COMPILER_EXPRESSION_SOURCE", t.value_allocator)
	if source_path == "" {
		return pbt.error("KVIST_PBT_COMPILER_EXPRESSION_SOURCE is not set")
	}
	command := [?]string{compiler_path, "eval", source_path, expression}
	process := pbt.process_run_with_options(t, command[:], {
		timeout_ms = COMPILER_PROCESS_TIMEOUT_MS,
		max_output_bytes = 16_384,
	})
	if !process.success {
		if process.stderr != "" {
			return pbt.fail(process.stderr)
		}
		if process.error != "" {
			return pbt.fail(process.error)
		}
		return pbt.fail(fmt.tprintf("compiler eval exited with %d", process.exit_code))
	}

	actual_text := strings.trim_space(process.stdout)
	actual, ok := strconv.parse_int(actual_text, 10)
	if !ok {
		return pbt.fail(fmt.tprintf("compiler eval returned a non-integer: %q", process.stdout))
	}
	if actual != expected {
		return pbt.fail(fmt.tprintf(
			"compiler Data destructuring mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_data_destructure_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Data_Destructure_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 13))
	value := pbt.draw(t, pbt.int_range(-8, 8))

	switch kind {
	case 0:
		stats.map_keys += 1
		stats.namespaced_keys += 1
		stats.as_binding += 1
		second := pbt.draw(t, pbt.int_range(-8, 8))
		third := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [value: Data {:x ")
		fmt.sbprintf(builder, "%d :y %d :point/z %d} ", value, second, third)
		strings.write_string(builder, "{:keys [x y] :point/keys [z] :as whole} value] (+ (* (int (data.int x)) 31) (* (int (data.int y)) 7) (* (int (data.int z)) 3) (count whole)))")
		return value * 31 + second * 7 + third * 3 + 3
	case 1:
		stats.explicit_entry += 1
		strings.write_string(builder, "(let [value: Data {:source ")
		fmt.sbprintf(builder, "%d} ", value)
		strings.write_string(builder, "{picked :source} value] (int (data.int picked)))")
		return value
	case 2:
		stats.map_keys += 1
		stats.default_missing += 1
		fallback := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [value: Data {} {:keys [missing] :or {missing ")
		fmt.sbprintf(builder, "%d", fallback)
		strings.write_string(builder, "}} value] (int (data.int missing)))")
		return fallback
	case 3:
		stats.map_keys += 1
		stats.nil_present += 1
		fallback := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [value: Data {:missing nil} {:keys [missing] :or {missing ")
		fmt.sbprintf(builder, "%d", fallback)
		strings.write_string(builder, "}} value] (if (data.nil? missing) 1 0))")
		return 1
	case 4:
		stats.namespaced_keys += 1
		strings.write_string(builder, "(let [value: Data {:point/x ")
		fmt.sbprintf(builder, "%d} ", value)
		strings.write_string(builder, "{:point/keys [x]} value] (int (data.int x)))")
		return value
	case 5:
		stats.string_symbol_keys += 1
		second := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [value: Data {\"external\" ")
		fmt.sbprintf(builder, "%d 'status %d} ", value, second)
		strings.write_string(builder, "{:strs [external] :syms [status]} value] (+ (* (int (data.int external)) 31) (int (data.int status))))")
		return value * 31 + second
	case 6:
		stats.sequence_position += 1
		second := pbt.draw(t, pbt.int_range(-8, 8))
		third := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [value: Data [%d %d %d] [first second] value] (+ (* (int (data.int first)) 31) (int (data.int second))))", value, second, third)
		return value * 31 + second
	case 7:
		stats.sequence_position += 1
		stats.missing_position += 1
		fmt.sbprintf(builder, "(let [value: Data [%d] [first second] value] (+ (* (int (data.int first)) 31) (if (data.nil? second) 1 0)))", value)
		return value * 31 + 1
	case 8:
		stats.sequence_position += 1
		stats.missing_position += 1
		stats.wrong_kind += 1
		fmt.sbprintf(builder, "(let [value: Data %d [first second] value] (+ (if (data.nil? first) 1 0) (if (data.nil? second) 2 0)))", value)
		return 3
	case 9:
		stats.sequence_position += 1
		stats.rest_binding += 1
		stats.as_binding += 1
		second := pbt.draw(t, pbt.int_range(-8, 8))
		third := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [value: Data [%d %d %d] [head & tail :as whole] value] (+ (* (int (data.int head)) 31) (* (count tail) 7) (count whole)))", value, second, third)
		return value * 31 + 2 * 7 + 3
	case 10:
		stats.sequence_position += 1
		stats.nested_binding += 1
		nested := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [value: Data [")
		fmt.sbprintf(builder, "%d ", value)
		strings.write_string(builder, "{:x ")
		fmt.sbprintf(builder, "%d}] [first ", nested)
		strings.write_string(builder, "{:keys [x]}] value] (+ (* (int (data.int first)) 31) (int (data.int x))))")
		return value * 31 + nested
	case 11:
		stats.for_sequence += 1
		a := pbt.draw(t, pbt.int_range(-8, 8))
		b := pbt.draw(t, pbt.int_range(-8, 8))
		c := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [rows: Data [[%d %d] [%d %d]] total 0] (for [[x y] rows] (set! total (+ total (int (data.int x)) (int (data.int y))))) total)", value, a, b, c)
		return value + a + b + c
	case 12:
		stats.for_sequence += 1
		stats.for_indexed += 1
		a := pbt.draw(t, pbt.int_range(-8, 8))
		b := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [rows: Data [[%d] [%d] [%d]] total 0] (for [index [x] rows] (set! total (+ total (* index (int (data.int x)))))) total)", value, a, b)
		return a + b * 2
	case 13:
		stats.for_map += 1
		stats.nil_source += 1
		second := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [rows: Data [{:x ")
		fmt.sbprintf(builder, "%d} ", value)
		strings.write_string(builder, "{:x ")
		fmt.sbprintf(builder, "%d}] empty: Data nil total 0] (for [", second)
		strings.write_string(builder, "{:keys [x]} rows] (set! total (+ total (int (data.int x))))) (for [[ignored] empty] (set! total -999)) total)")
		return value + second
	}
	return 0
}
