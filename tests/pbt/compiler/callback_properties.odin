// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Callback_Stats :: struct {
	noncapturing:      int,
	single_capture:    int,
	multiple_captures: int,
	forwarded_capture: int,
	captured_fold:     int,
	noncapturing_fold: int,
	indexed_capture:   int,
	conditional_body:  int,
	stored_proc:       int,
	selected_proc:     int,
	shadowed_parameter: int,
	aggregate_capture: int,
}

generated_compiler_callbacks_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Callback_Stats
	expected := write_compiler_callback_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.noncapturing > 0, 3, "noncapturing")
	pbt.cover(t, stats.single_capture > 0, 3, "single-capture")
	pbt.cover(t, stats.multiple_captures > 0, 3, "multiple-captures")
	pbt.cover(t, stats.forwarded_capture > 0, 3, "forwarded-capture")
	pbt.cover(t, stats.captured_fold > 0, 3, "captured-fold")
	pbt.cover(t, stats.noncapturing_fold > 0, 3, "noncapturing-fold")
	pbt.cover(t, stats.indexed_capture > 0, 3, "indexed-capture")
	pbt.cover(t, stats.conditional_body > 0, 3, "conditional-body")
	pbt.cover(t, stats.stored_proc > 0, 3, "stored-proc")
	pbt.cover(t, stats.selected_proc > 0, 3, "selected-proc")
	pbt.cover(t, stats.shadowed_parameter > 0, 3, "shadowed-parameter")
	pbt.cover(t, stats.aggregate_capture > 0, 3, "aggregate-capture")

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
			"compiler callback mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_callback_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Callback_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 11))
	value := pbt.draw(t, pbt.int_range(-8, 8))

	switch kind {
	case 0:
		stats.noncapturing += 1
		scale := pbt.draw(t, pbt.int_range(-3, 3))
		offset := pbt.draw(t, pbt.int_range(-5, 5))
		fmt.sbprintf(builder, "(pbt-apply-int (fn [x: int] -> int (+ (* x %d) %d)) %d)", scale, offset, value)
		return value * scale + offset
	case 1:
		stats.single_capture += 1
		offset := pbt.draw(t, pbt.int_range(-5, 5))
		fmt.sbprintf(builder, "(let [offset %d] (pbt-apply-int (fn [x: int] -> int (+ x offset)) %d))", offset, value)
		return value + offset
	case 2:
		stats.multiple_captures += 1
		stats.aggregate_capture += 1
		scale := pbt.draw(t, pbt.int_range(-3, 3))
		offset := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(let [point (Pbt-Point {x: ")
		fmt.sbprintf(builder, "%d y: 0 weight: 0 active?: false}) offset %d] (pbt-apply-int (fn [x: int] -> int (+ (* x point.x) offset)) %d))", scale, offset, value)
		return value * scale + offset
	case 3:
		stats.forwarded_capture += 1
		offset := pbt.draw(t, pbt.int_range(-5, 5))
		fmt.sbprintf(builder, "(let [offset %d] (pbt-apply-int-twice (fn [x: int] -> int (+ x offset)) %d))", offset, value)
		return value + offset + value + 1 + offset
	case 4:
		stats.captured_fold += 1
		values, length := draw_compiler_loop_values(t, 1, 6)
		initial := pbt.draw(t, pbt.int_range(-8, 8))
		offset := pbt.draw(t, pbt.int_range(-4, 4))
		fmt.sbprintf(builder, "(let [offset %d xs ", offset)
		write_compiler_fixed_int_array(builder, values[:length])
		fmt.sbprintf(builder, "] (pbt-fold-int (fn [acc: int, x: int] -> int (+ acc x offset)) %d (slice xs 0)))", initial)
		return initial + compiler_loop_sum(values[:length]) + length * offset
	case 5:
		stats.noncapturing_fold += 1
		values, length := draw_compiler_loop_values(t, 1, 6)
		initial := pbt.draw(t, pbt.int_range(-8, 8))
		factor := pbt.draw(t, pbt.int_range(-3, 3))
		strings.write_string(builder, "(let [xs ")
		write_compiler_fixed_int_array(builder, values[:length])
		fmt.sbprintf(builder, "] (pbt-fold-int (fn [acc: int, x: int] -> int (+ acc (* x %d))) %d (slice xs 0)))", factor, initial)
		return initial + compiler_loop_sum(values[:length]) * factor
	case 6:
		stats.indexed_capture += 1
		values, length := draw_compiler_loop_values(t, 1, 6)
		initial := pbt.draw(t, pbt.int_range(-8, 8))
		weight := pbt.draw(t, pbt.int_range(-4, 4))
		fmt.sbprintf(builder, "(let [weight %d xs ", weight)
		write_compiler_fixed_int_array(builder, values[:length])
		fmt.sbprintf(builder, "] (pbt-fold-indexed (fn [acc: int, value: int, index: int] -> int (+ acc value (* index weight))) %d (slice xs 0)))", initial)
		return initial + compiler_loop_sum(values[:length]) + weight * length * (length - 1) / 2
	case 7:
		stats.conditional_body += 1
		threshold := pbt.draw(t, pbt.int_range(-5, 5))
		fmt.sbprintf(builder, "(let [threshold %d] (pbt-apply-int (fn [x: int] -> int (if (> x threshold) (* x 2) (- 0 x))) %d))", threshold, value)
		return value * 2 if value > threshold else -value
	case 8:
		stats.stored_proc += 1
		offset := pbt.draw(t, pbt.int_range(-5, 5))
		fmt.sbprintf(builder, "(let [f (fn [x: int] -> int (+ x %d))] (f %d))", offset, value)
		return value + offset
	case 9:
		stats.selected_proc += 1
		condition := pbt.draw(t, pbt.boolean())
		left_offset := pbt.draw(t, pbt.int_range(-5, 5))
		right_offset := pbt.draw(t, pbt.int_range(-5, 5))
		fmt.sbprintf(builder, "(let [f: (fn [x: int] -> int) (if %t (fn [x: int] -> int (+ x %d)) (fn [x: int] -> int (+ x %d)))] (f %d))", condition, left_offset, right_offset, value)
		return value + (left_offset if condition else right_offset)
	case 10:
		stats.shadowed_parameter += 1
		fmt.sbprintf(builder, "(let [base %d] (pbt-apply-int (fn [base: int] -> int (* base base)) base))", value)
		return value * value
	case 11:
		stats.aggregate_capture += 1
		x := pbt.draw(t, pbt.int_range(-5, 5))
		y := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(let [point (Pbt-Point {x: ")
		fmt.sbprintf(builder, "%d y: %d weight: 0 active?: false})] (pbt-apply-int (fn [value: int] -> int (+ value point.x point.y)) %d))", x, y, value)
		return value + x + y
	}
	return 0
}
