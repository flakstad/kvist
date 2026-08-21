// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Data_Pattern_Stats :: struct {
	exact_literal:     int,
	literal_hit:       int,
	literal_miss:      int,
	map_open:          int,
	map_miss:          int,
	sequence_exact:    int,
	sequence_rest:     int,
	nested_pattern:    int,
	as_pattern:        int,
	kind_pattern:      int,
	set_pattern:       int,
	first_match:       int,
	wildcard_fallback: int,
	capture:           int,
}

generated_compiler_data_patterns_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Data_Pattern_Stats
	expected := write_compiler_data_pattern_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.exact_literal > 0, 3, "exact-literal")
	pbt.cover(t, stats.literal_hit > 0, 3, "literal-hit")
	pbt.cover(t, stats.literal_miss > 0, 3, "literal-miss")
	pbt.cover(t, stats.map_open > 0, 3, "map-open")
	pbt.cover(t, stats.map_miss > 0, 3, "map-miss")
	pbt.cover(t, stats.sequence_exact > 0, 3, "sequence-exact")
	pbt.cover(t, stats.sequence_rest > 0, 3, "sequence-rest")
	pbt.cover(t, stats.nested_pattern > 0, 3, "nested-pattern")
	pbt.cover(t, stats.as_pattern > 0, 3, "as-pattern")
	pbt.cover(t, stats.kind_pattern > 0, 3, "kind-pattern")
	pbt.cover(t, stats.set_pattern > 0, 3, "set-pattern")
	pbt.cover(t, stats.first_match > 0, 3, "first-match")
	pbt.cover(t, stats.wildcard_fallback > 0, 3, "wildcard-fallback")
	pbt.cover(t, stats.capture > 0, 3, "capture")

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
			"compiler Data pattern mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_data_pattern_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Data_Pattern_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 12))
	value := pbt.draw(t, pbt.int_range(-8, 8))

	switch kind {
	case 0:
		stats.exact_literal += 1
		hit := pbt.draw(t, pbt.boolean())
		pattern := value if hit else value + 1
		if hit {
			stats.literal_hit += 1
		} else {
			stats.literal_miss += 1
			stats.wildcard_fallback += 1
		}
		fmt.sbprintf(builder, "(let [value: Data %d result: int (match value %d 1 _ 0)] result)", value, pattern)
		return 1 if hit else 0
	case 1:
		stats.exact_literal += 1
		hit := pbt.draw(t, pbt.boolean())
		if hit {
			stats.literal_hit += 1
			strings.write_string(builder, "(let [value: Data :ready result: int (match value :ready 7 :else 0)] result)")
			return 7
		}
		stats.literal_miss += 1
		stats.wildcard_fallback += 1
		strings.write_string(builder, "(let [value: Data :running result: int (match value :ready 7 :else 0)] result)")
		return 0
	case 2:
		stats.map_open += 1
		stats.capture += 1
		x := pbt.draw(t, pbt.int_range(-8, 8))
		extra := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [value: Data {:kind :point :x ")
		fmt.sbprintf(builder, "%d :extra %d} result: int (match value ", x, extra)
		strings.write_string(builder, "{:kind :point :x captured} (int (data.int captured)) :else -99)] result)")
		return x
	case 3:
		stats.map_miss += 1
		stats.wildcard_fallback += 1
		strings.write_string(builder, "(let [value: Data {:kind :point} result: int (match value {:kind :point :missing _} 1 :else 0)] result)")
		return 0
	case 4:
		stats.sequence_exact += 1
		stats.capture += 1
		second := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [value: Data [%d %d] result: int (match value [first second] (+ (* (int (data.int first)) 31) (int (data.int second))) :else -99)] result)", value, second)
		return value * 31 + second
	case 5:
		stats.sequence_exact += 1
		stats.literal_miss += 1
		stats.wildcard_fallback += 1
		fmt.sbprintf(builder, "(let [value: Data [%d %d %d] result: int (match value [first second] 1 :else 0)] result)", value, value + 1, value + 2)
		return 0
	case 6:
		stats.sequence_rest += 1
		stats.capture += 1
		second := pbt.draw(t, pbt.int_range(-8, 8))
		third := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [value: Data [%d %d %d] result: int (match value [head & tail] (+ (* (int (data.int head)) 31) (count tail)) :else -99)] result)", value, second, third)
		return value * 31 + 2
	case 7:
		stats.sequence_rest += 1
		stats.as_pattern += 1
		stats.kind_pattern += 1
		stats.capture += 1
		fmt.sbprintf(builder, "(let [value: Data [%d %d %d] result: int (match value (as whole (kind :vector [head & tail])) (+ (* (count whole) 31) (count tail)) :else -99)] result)", value, value + 1, value + 2)
		return 3 * 31 + 2
	case 8:
		stats.map_open += 1
		stats.sequence_exact += 1
		stats.nested_pattern += 1
		stats.capture += 1
		second := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [value: Data {:items [")
		fmt.sbprintf(builder, "%d %d] :extra true} result: int (match value ", value, second)
		strings.write_string(builder, "{:items [first second]} (+ (* (int (data.int first)) 31) (int (data.int second))) :else -99)] result)")
		return value * 31 + second
	case 9:
		stats.set_pattern += 1
		hit := pbt.draw(t, pbt.boolean())
		if hit {
			stats.literal_hit += 1
			strings.write_string(builder, "(let [value: Data #{:ready :running} result: int (match value #{:ready :running} 1 :else 0)] result)")
			return 1
		}
		stats.literal_miss += 1
		stats.wildcard_fallback += 1
		strings.write_string(builder, "(let [value: Data #{:ready :done} result: int (match value #{:ready :running} 1 :else 0)] result)")
		return 0
	case 10:
		stats.kind_pattern += 1
		stats.capture += 1
		length := pbt.draw(t, pbt.int_range(0, 6))
		strings.write_string(builder, "(let [value: Data \"")
		for _ in 0 ..< length {
			strings.write_byte(builder, 'x')
		}
		strings.write_string(builder, "\" result: int (match value (kind :string captured) (count (data.string captured)) :else -1)] result)")
		return length
	case 11:
		stats.map_open += 1
		stats.first_match += 1
		stats.capture += 1
		y := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [value: Data {:x ")
		fmt.sbprintf(builder, "%d :y %d} result: int (match value ", value, y)
		strings.write_string(builder, "{:x captured} (+ 100 (int (data.int captured))) {:x captured :y other} (+ 200 (int (data.int other))) :else -99)] result)")
		return 100 + value
	case 12:
		stats.exact_literal += 1
		stats.literal_miss += 1
		stats.wildcard_fallback += 1
		fallback := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [value: Data true result: int (match value false 1 _ %d)] result)", fallback)
		return fallback
	}
	return 0
}
