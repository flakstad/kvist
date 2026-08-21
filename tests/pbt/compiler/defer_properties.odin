// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Defer_Stats :: struct {
	single_call:        int,
	multi_form:         int,
	lifo:               int,
	nested_scope:       int,
	normal_before_exit: int,
	late_binding:       int,
	conditional_scope:  int,
	loop_scope:         int,
	early_return:       int,
	pointer_target:     int,
	field_target:       int,
	three_deep:         int,
}

generated_compiler_defer_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Defer_Stats
	expected := write_compiler_defer_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.single_call > 0, 3, "single-call")
	pbt.cover(t, stats.multi_form > 0, 3, "multi-form")
	pbt.cover(t, stats.lifo > 0, 3, "lifo")
	pbt.cover(t, stats.nested_scope > 0, 3, "nested-scope")
	pbt.cover(t, stats.normal_before_exit > 0, 3, "normal-before-exit")
	pbt.cover(t, stats.late_binding > 0, 3, "late-binding")
	pbt.cover(t, stats.conditional_scope > 0, 3, "conditional-scope")
	pbt.cover(t, stats.loop_scope > 0, 3, "loop-scope")
	pbt.cover(t, stats.early_return > 0, 3, "early-return")
	pbt.cover(t, stats.pointer_target > 0, 3, "pointer-target")
	pbt.cover(t, stats.field_target > 0, 3, "field-target")
	pbt.cover(t, stats.three_deep > 0, 3, "three-deep")

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
			"compiler defer mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_defer_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Defer_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 11))
	initial := pbt.draw(t, pbt.int_range(-5, 5))

	switch kind {
	case 0:
		stats.single_call += 1
		stats.pointer_target += 1
		multiplier := pbt.draw(t, pbt.int_range(-2, 2))
		addend := pbt.draw(t, pbt.int_range(-4, 4))
		fmt.sbprintf(builder, "(let [result %d] (block (defer (pbt-defer-step! (addr result) %d %d))) result)", initial, multiplier, addend)
		return initial * multiplier + addend
	case 1:
		stats.single_call += 1
		stats.lifo += 1
		first_multiplier := pbt.draw(t, pbt.int_range(-2, 2))
		first_addend := pbt.draw(t, pbt.int_range(-4, 4))
		second_multiplier := pbt.draw(t, pbt.int_range(-2, 2))
		second_addend := pbt.draw(t, pbt.int_range(-4, 4))
		fmt.sbprintf(builder, "(let [result %d] (block (defer (pbt-defer-step! (addr result) %d %d)) (defer (pbt-defer-step! (addr result) %d %d))) result)", initial, first_multiplier, first_addend, second_multiplier, second_addend)
		return (initial * second_multiplier + second_addend) * first_multiplier + first_addend
	case 2:
		stats.multi_form += 1
		first_addend := pbt.draw(t, pbt.int_range(-4, 4))
		multiplier := pbt.draw(t, pbt.int_range(-2, 2))
		fmt.sbprintf(builder, "(let [result %d] (block (defer (set! result (+ result %d)) (set! result (* result %d)))) result)", initial, first_addend, multiplier)
		return (initial + first_addend) * multiplier
	case 3:
		stats.single_call += 1
		stats.nested_scope += 1
		outer_multiplier := pbt.draw(t, pbt.int_range(-2, 2))
		outer_addend := pbt.draw(t, pbt.int_range(-4, 4))
		inner_multiplier := pbt.draw(t, pbt.int_range(-2, 2))
		inner_addend := pbt.draw(t, pbt.int_range(-4, 4))
		fmt.sbprintf(builder, "(let [result %d] (block (defer (pbt-defer-step! (addr result) %d %d)) (block (defer (pbt-defer-step! (addr result) %d %d)))) result)", initial, outer_multiplier, outer_addend, inner_multiplier, inner_addend)
		return (initial * inner_multiplier + inner_addend) * outer_multiplier + outer_addend
	case 4:
		stats.single_call += 1
		stats.normal_before_exit += 1
		ordinary := pbt.draw(t, pbt.int_range(-5, 5))
		multiplier := pbt.draw(t, pbt.int_range(-2, 2))
		addend := pbt.draw(t, pbt.int_range(-4, 4))
		fmt.sbprintf(builder, "(let [result %d] (block (defer (pbt-defer-step! (addr result) %d %d)) (set! result %d)) result)", initial, multiplier, addend, ordinary)
		return ordinary * multiplier + addend
	case 5:
		stats.single_call += 1
		stats.late_binding += 1
		before := pbt.draw(t, pbt.int_range(-4, 4))
		after := pbt.draw(t, pbt.int_range(-4, 4))
		fmt.sbprintf(builder, "(let [result %d addend %d] (block (defer (pbt-defer-step! (addr result) 1 addend)) (set! addend %d)) result)", initial, before, after)
		return initial + after
	case 6:
		stats.single_call += 1
		stats.conditional_scope += 1
		enabled := pbt.draw(t, pbt.boolean())
		multiplier := pbt.draw(t, pbt.int_range(-2, 2))
		addend := pbt.draw(t, pbt.int_range(-4, 4))
		ordinary := pbt.draw(t, pbt.int_range(-4, 4))
		fmt.sbprintf(builder, "(let [result %d] (block (when %t (defer (pbt-defer-step! (addr result) %d %d))) (set! result (+ result %d))) result)", initial, enabled, multiplier, addend, ordinary)
		conditional := initial * multiplier + addend if enabled else initial
		return conditional + ordinary
	case 7:
		stats.single_call += 1
		stats.loop_scope += 1
		values, length := draw_compiler_loop_values(t, 1, 6)
		strings.write_string(builder, "(let [result ")
		fmt.sbprintf(builder, "%d values ", initial)
		write_compiler_fixed_int_array(builder, values[:length])
		strings.write_string(builder, "] (for [value values] (block (defer (pbt-defer-step! (addr result) 1 value)))) result)")
		return initial + compiler_loop_sum(values[:length])
	case 8:
		stats.single_call += 1
		stats.early_return += 1
		stats.pointer_target += 1
		returned := pbt.draw(t, pbt.int_range(-5, 5))
		multiplier := pbt.draw(t, pbt.int_range(-2, 2))
		addend := pbt.draw(t, pbt.int_range(-4, 4))
		fmt.sbprintf(builder, "(let [result %d returned (pbt-defer-return! (addr result) %d %d %d)] (+ (* result 31) returned))", initial, returned, multiplier, addend)
		return (initial * multiplier + addend) * 31 + returned
	case 9:
		stats.single_call += 1
		stats.field_target += 1
		x := pbt.draw(t, pbt.int_range(-5, 5))
		y := pbt.draw(t, pbt.int_range(-5, 5))
		multiplier := pbt.draw(t, pbt.int_range(-2, 2))
		addend := pbt.draw(t, pbt.int_range(-4, 4))
		strings.write_string(builder, "(let [point (Pbt-Point {x: ")
		fmt.sbprintf(builder, "%d y: %d weight: 0 active?: false})] (block (defer (pbt-defer-step! (addr point.x) %d %d))) (+ (* point.x 31) point.y))", x, y, multiplier, addend)
		return (x * multiplier + addend) * 31 + y
	case 10:
		stats.single_call += 1
		stats.lifo += 1
		stats.three_deep += 1
		first := pbt.draw(t, pbt.int_range(-3, 3))
		second := pbt.draw(t, pbt.int_range(-3, 3))
		third := pbt.draw(t, pbt.int_range(-3, 3))
		fmt.sbprintf(builder, "(let [result %d] (block (defer (pbt-defer-step! (addr result) 10 %d)) (defer (pbt-defer-step! (addr result) 10 %d)) (defer (pbt-defer-step! (addr result) 10 %d))) result)", initial, first, second, third)
		return ((initial * 10 + third) * 10 + second) * 10 + first
	case 11:
		stats.multi_form += 1
		stats.nested_scope += 1
		outer_addend := pbt.draw(t, pbt.int_range(-4, 4))
		inner_addend := pbt.draw(t, pbt.int_range(-4, 4))
		fmt.sbprintf(builder, "(let [result %d] (block (defer (set! result (+ result %d)) (mut! result += 0)) (block (defer (set! result (+ result %d)) (mut! result += 0)))) result)", initial, outer_addend, inner_addend)
		return initial + inner_addend + outer_addend
	}
	return 0
}
