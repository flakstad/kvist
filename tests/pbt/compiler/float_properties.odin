// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Float_Stats :: struct {
	add:       int,
	subtract:  int,
	multiply:  int,
	divide:    int,
	minimum:   int,
	maximum:   int,
	if_form:   int,
	let_form:  int,
	call:      int,
	cond_form: int,
	case_form: int,
}

generated_compiler_float_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	depth := pbt.draw(t, pbt.int_range(1, 3))
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Float_Stats
	expected := write_compiler_float_expression(t, &builder, depth, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%.17g", expression, expected))

	pbt.cover(t, stats.add > 0, 5, "addition")
	pbt.cover(t, stats.subtract > 0, 5, "subtraction")
	pbt.cover(t, stats.multiply > 0, 5, "multiplication")
	pbt.cover(t, stats.divide > 0, 5, "division")
	pbt.cover(t, stats.minimum > 0, 5, "minimum")
	pbt.cover(t, stats.maximum > 0, 5, "maximum")
	pbt.cover(t, stats.if_form > 0, 5, "if")
	pbt.cover(t, stats.let_form > 0, 5, "let")
	pbt.cover(t, stats.call > 0, 5, "function-call")
	pbt.cover(t, stats.cond_form > 0, 5, "cond")
	pbt.cover(t, stats.case_form > 0, 5, "case")

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
	actual, ok := strconv.parse_f64(actual_text)
	if !ok {
		return pbt.fail(fmt.tprintf("compiler eval returned a non-float: %q", process.stdout))
	}
	delta := compiler_float_abs(actual - expected)
	scale := max(1.0, compiler_float_abs(expected))
	if delta > 1e-9 * scale {
		return pbt.fail(fmt.tprintf(
			"compiler float expression mismatch: expected=%.17g actual=%.17g delta=%.17g expression=%s",
			expected,
			actual,
			delta,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_float_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	depth: int,
	stats: ^Compiler_Float_Stats,
) -> f64 {
	if depth <= 0 {
		return write_compiler_float_literal(t, builder)
	}

	kind := pbt.draw(t, pbt.int_range(0, 11))
	switch kind {
	case 0:
		return write_compiler_float_literal(t, builder)
	case 1:
		stats.add += 1
		strings.write_string(builder, "(+ ")
		left := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return left + right
	case 2:
		stats.subtract += 1
		strings.write_string(builder, "(- ")
		left := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return left - right
	case 3:
		stats.multiply += 1
		strings.write_string(builder, "(* ")
		left := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return left * right
	case 4:
		stats.divide += 1
		denominator_tenths := pbt.draw(t, pbt.int_range(1, 50))
		if pbt.draw(t, pbt.boolean()) {
			denominator_tenths = -denominator_tenths
		}
		strings.write_string(builder, "(/ ")
		value := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		denominator := write_compiler_float_tenths(builder, denominator_tenths)
		strings.write_byte(builder, ')')
		return value / denominator
	case 5:
		stats.minimum += 1
		strings.write_string(builder, "(min ")
		left := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return min(left, right)
	case 6:
		stats.maximum += 1
		strings.write_string(builder, "(max ")
		left := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return max(left, right)
	case 7:
		stats.if_form += 1
		bool_stats: Compiler_Bool_Stats
		strings.write_string(builder, "(if (identity-bool ")
		condition := write_compiler_boolean_expression(t, builder, depth - 1, &bool_stats)
		strings.write_string(builder, ") (identity-float ")
		when_true := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, ") (identity-float ")
		when_false := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, "))")
		return when_true if condition else when_false
	case 8:
		stats.let_form += 1
		strings.write_string(builder, "(let [x: f64 ")
		value := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, " result: f64 (+ x ")
		offset := write_compiler_float_literal(t, builder)
		strings.write_string(builder, ")] result)")
		return value + offset
	case 9:
		stats.call += 1
		strings.write_string(builder, "(affine-float ")
		value := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		scale := write_compiler_float_literal(t, builder)
		strings.write_byte(builder, ' ')
		offset := write_compiler_float_literal(t, builder)
		strings.write_byte(builder, ')')
		return value * scale + offset
	case 10:
		stats.cond_form += 1
		bool_stats: Compiler_Bool_Stats
		strings.write_string(builder, "(cond (identity-bool ")
		condition := write_compiler_boolean_expression(t, builder, depth - 1, &bool_stats)
		strings.write_string(builder, ") (identity-float ")
		when_true := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, ") :else (identity-float ")
		when_false := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, "))")
		return when_true if condition else when_false
	case 11:
		stats.case_form += 1
		match := pbt.draw(t, pbt.int_range(-3, 3))
		int_stats: Compiler_Expression_Stats
		strings.write_string(builder, "(case ")
		value := write_compiler_expression(t, builder, depth - 1, &int_stats)
		fmt.sbprintf(builder, " %d (identity-float ", match)
		when_match := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, ") (identity-float ")
		fallback := write_compiler_float_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, "))")
		return when_match if value == match else fallback
	}
	return 0
}

write_compiler_float_literal :: proc(t: ^pbt.T, builder: ^strings.Builder) -> f64 {
	return write_compiler_float_tenths(builder, pbt.draw(t, pbt.int_range(-80, 80)))
}

write_compiler_float_tenths :: proc(builder: ^strings.Builder, tenths: int) -> f64 {
	whole := tenths / 10
	fraction := tenths % 10
	if fraction < 0 {
		fraction = -fraction
	}
	if tenths < 0 && whole == 0 {
		fmt.sbprintf(builder, "-0.%d", fraction)
	} else {
		fmt.sbprintf(builder, "%d.%d", whole, fraction)
	}
	return f64(tenths) / 10.0
}

compiler_float_abs :: proc(value: f64) -> f64 {
	return -value if value < 0 else value
}
