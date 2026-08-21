// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

COMPILER_EXPRESSION_TAGS := [?]string{"compiler", "expression", "model", "external", "slow"}
COMPILER_DIAGNOSTIC_TAGS := [?]string{"compiler", "diagnostic", "invalid", "model"}
COMPILER_PROCESS_TIMEOUT_MS :: 120_000

Compiler_Expression_Stats :: struct {
	add:       int,
	subtract:  int,
	multiply:  int,
	if_form:   int,
	let_form:  int,
	call:      int,
	cond_form: int,
	case_form: int,
	thread:    int,
}

Compiler_Bool_Stats :: struct {
	less_than:    int,
	equal:        int,
	and_form:     int,
	or_form:      int,
	not_form:     int,
	if_form:      int,
	let_form:     int,
	call:         int,
	cond_form:    int,
	case_form:    int,
	short_circuit_and: int,
	short_circuit_or:  int,
}

generated_compiler_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	depth := pbt.draw(t, pbt.int_range(1, 3))
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Expression_Stats
	expected := write_compiler_expression(t, &builder, depth, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.add > 0, 5, "addition")
	pbt.cover(t, stats.subtract > 0, 5, "subtraction")
	pbt.cover(t, stats.multiply > 0, 5, "multiplication")
	pbt.cover(t, stats.if_form > 0, 5, "if")
	pbt.cover(t, stats.let_form > 0, 5, "let")
	pbt.cover(t, stats.call > 0, 5, "function-call")
	pbt.cover(t, stats.cond_form > 0, 5, "cond")
	pbt.cover(t, stats.case_form > 0, 5, "case")
	pbt.cover(t, stats.thread > 0, 5, "thread-first")

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
			"compiler expression mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

generated_compiler_boolean_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	depth := pbt.draw(t, pbt.int_range(1, 3))
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Bool_Stats
	expected := write_compiler_boolean_expression(t, &builder, depth, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%t", expression, expected))

	pbt.cover(t, stats.less_than > 0, 5, "less-than")
	pbt.cover(t, stats.equal > 0, 5, "equality")
	pbt.cover(t, stats.and_form > 0, 5, "and")
	pbt.cover(t, stats.or_form > 0, 5, "or")
	pbt.cover(t, stats.not_form > 0, 5, "not")
	pbt.cover(t, stats.if_form > 0, 5, "if")
	pbt.cover(t, stats.let_form > 0, 5, "let")
	pbt.cover(t, stats.call > 0, 5, "function-call")
	pbt.cover(t, stats.cond_form > 0, 5, "cond")
	pbt.cover(t, stats.case_form > 0, 5, "case")
	pbt.cover(t, stats.short_circuit_and > 0, 3, "short-circuit-and")
	pbt.cover(t, stats.short_circuit_or > 0, 3, "short-circuit-or")

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
	if actual_text != "true" && actual_text != "false" {
		return pbt.fail(fmt.tprintf("compiler eval returned a non-boolean: %q", process.stdout))
	}
	actual := actual_text == "true"
	if actual != expected {
		return pbt.fail(fmt.tprintf(
			"compiler boolean expression mismatch: expected=%t actual=%t expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_boolean_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	depth: int,
	stats: ^Compiler_Bool_Stats,
) -> bool {
	if depth <= 0 {
		value := pbt.draw(t, pbt.boolean())
		fmt.sbprintf(builder, "%t", value)
		return value
	}

	kind := pbt.draw(t, pbt.int_range(0, 11))
	switch kind {
	case 0:
		value := pbt.draw(t, pbt.boolean())
		fmt.sbprintf(builder, "%t", value)
		return value
	case 1:
		stats.less_than += 1
		int_stats: Compiler_Expression_Stats
		strings.write_string(builder, "(< ")
		left := write_compiler_expression(t, builder, depth - 1, &int_stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_expression(t, builder, depth - 1, &int_stats)
		strings.write_byte(builder, ')')
		return left < right
	case 2:
		stats.equal += 1
		int_stats: Compiler_Expression_Stats
		strings.write_string(builder, "(= ")
		left := write_compiler_expression(t, builder, depth - 1, &int_stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_expression(t, builder, depth - 1, &int_stats)
		strings.write_byte(builder, ')')
		return left == right
	case 3:
		stats.and_form += 1
		strings.write_string(builder, "(and ")
		left := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return left && right
	case 4:
		stats.or_form += 1
		strings.write_string(builder, "(or ")
		left := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return left || right
	case 5:
		stats.not_form += 1
		strings.write_string(builder, "(not ")
		value := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return !value
	case 6:
		stats.if_form += 1
		strings.write_string(builder, "(if (identity-bool ")
		condition := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, ") ")
		when_true := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		when_false := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return when_true if condition else when_false
	case 7:
		stats.let_form += 1
		strings.write_string(builder, "(let [x ")
		value := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, " result: bool (not x)] result)")
		return !value
	case 8:
		stats.call += 1
		int_stats: Compiler_Expression_Stats
		strings.write_string(builder, "(nonnegative? ")
		value := write_compiler_expression(t, builder, depth - 1, &int_stats)
		strings.write_byte(builder, ')')
		return value >= 0
	case 9:
		stats.cond_form += 1
		strings.write_string(builder, "(cond (identity-bool ")
		condition := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, ") ")
		when_true := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, " :else ")
		when_false := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return when_true if condition else when_false
	case 10:
		stats.case_form += 1
		match := pbt.draw(t, pbt.int_range(-3, 3))
		int_stats: Compiler_Expression_Stats
		strings.write_string(builder, "(case ")
		value := write_compiler_expression(t, builder, depth - 1, &int_stats)
		fmt.sbprintf(builder, " %d ", match)
		when_match := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		fallback := write_compiler_boolean_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return when_match if value == match else fallback
	case 11:
		use_and := pbt.draw(t, pbt.boolean())
		if use_and {
			stats.short_circuit_and += 1
			strings.write_string(builder, "(and false (zero-quotient? 1 0))")
			return false
		}
		stats.short_circuit_or += 1
		strings.write_string(builder, "(or true (zero-quotient? 1 0))")
		return true
	}
	return false
}

write_compiler_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	depth: int,
	stats: ^Compiler_Expression_Stats,
) -> int {
	if depth <= 0 {
		value := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "%d", value)
		return value
	}

	kind := pbt.draw(t, pbt.int_range(0, 9))
	switch kind {
	case 0:
		value := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "%d", value)
		return value
	case 1:
		stats.add += 1
		strings.write_string(builder, "(+ ")
		left := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return left + right
	case 2:
		stats.subtract += 1
		strings.write_string(builder, "(- ")
		left := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return left - right
	case 3:
		stats.multiply += 1
		strings.write_string(builder, "(* ")
		left := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return left * right
	case 4:
		stats.if_form += 1
		strings.write_string(builder, "(if (< ")
		left := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		right := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, ") ")
		when_true := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		when_false := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return when_true if left < right else when_false
	case 5:
		stats.let_form += 1
		offset := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(let [x ")
		value := write_compiler_expression(t, builder, depth - 1, stats)
		fmt.sbprintf(builder, " result: int (+ x %d)] result)", offset)
		return value + offset
	case 6:
		stats.call += 1
		scale := pbt.draw(t, pbt.int_range(-3, 3))
		offset := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(affine ")
		value := write_compiler_expression(t, builder, depth - 1, stats)
		fmt.sbprintf(builder, " %d %d)", scale, offset)
		return value * scale + offset
	case 7:
		stats.cond_form += 1
		pivot := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(cond (< ")
		value := write_compiler_expression(t, builder, depth - 1, stats)
		fmt.sbprintf(builder, " %d) ", pivot)
		when_true := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, " :else ")
		when_false := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return when_true if value < pivot else when_false
	case 8:
		stats.case_form += 1
		match := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(case ")
		value := write_compiler_expression(t, builder, depth - 1, stats)
		fmt.sbprintf(builder, " %d ", match)
		when_match := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		fallback := write_compiler_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return when_match if value == match else fallback
	case 9:
		stats.thread += 1
		offset := pbt.draw(t, pbt.int_range(-5, 5))
		scale := pbt.draw(t, pbt.int_range(-3, 3))
		strings.write_string(builder, "(-> ")
		value := write_compiler_expression(t, builder, depth - 1, stats)
		fmt.sbprintf(builder, " (+ %d) (* %d))", offset, scale)
		return (value + offset) * scale
	}
	return 0
}

main :: proc() {
	properties := [?]pbt.Property_Case{
		{
			name = "generated compiler expressions match model",
			property = generated_compiler_expressions_match_model,
			description = "generated arithmetic, branching, binding, calls, and macro expressions compile and execute like an independent integer model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler boolean expressions match model",
			property = generated_compiler_boolean_expressions_match_model,
			description = "generated comparisons, boolean operators, branching, binding, calls, and short-circuit forms compile and execute like an independent boolean model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler string expressions match model",
			property = generated_compiler_string_expressions_match_model,
			description = "generated literals, string transforms, branching, binding, and calls compile and execute like an independent string model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler float expressions match model",
			property = generated_compiler_float_expressions_match_model,
			description = "generated floating-point arithmetic, extrema, branching, binding, and calls compile and execute within model tolerance",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler array expressions match model",
			property = generated_compiler_array_expressions_match_model,
			description = "generated native array literals, indexing, slicing, destructuring, membership, and mutation compile and execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler struct expressions match model",
			property = generated_compiler_struct_expressions_match_model,
			description = "generated struct literals, field reads, copying, nested value updates, mutation, and branching compile and execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler map and set expressions match model",
			property = generated_compiler_map_set_expressions_match_model,
			description = "generated native map and set literals, lookup, membership, mutation, typed empties, and branching compile and execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler enum expressions match model",
			property = generated_compiler_enum_expressions_match_model,
			description = "generated sparse enum selectors, casts, cases, branching, struct fields, mutation, and arrays compile and execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler union expressions match model",
			property = generated_compiler_union_expressions_match_model,
			description = "generated tagged union payloads, type cases, branching, nesting, updates, mutation, copies, and arrays compile and execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler control flow matches model",
			property = generated_compiler_control_flow_matches_model,
			description = "generated bounded for and while loops with indexing, nesting, break, continue, and empty inputs execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler multi-return expressions match model",
			property = generated_compiler_multi_return_expressions_match_model,
			description = "generated multi-return bindings, discards, boolean guards, chained branches, loop guards, early returns, and optional fallbacks execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler callbacks match model",
			property = generated_compiler_callbacks_match_model,
			description = "generated noncapturing functions, explicit captures, forwarded callbacks, folds, indexed callbacks, proc values, and aggregate captures execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler pointer expressions match model",
			property = generated_compiler_pointer_expressions_match_model,
			description = "generated address, dereference, pointee mutation, aliasing, function-boundary, struct-field, array-cell, and nested pointer expressions execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler defer expressions match model",
			property = generated_compiler_defer_expressions_match_model,
			description = "generated single-call and multi-form defers, LIFO ordering, nested and conditional scopes, loop scopes, late binding, and early returns execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler Data patterns match model",
			property = generated_compiler_data_patterns_match_model,
			description = "generated literal, map, sequence, rest, nested, as, kind, set, priority, capture, and fallback Data patterns execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler Data destructuring matches model",
			property = generated_compiler_data_destructuring_matches_model,
			description = "generated map-key, default, namespaced, string, symbol, sequential, rest, as, nested, and loop Data bindings execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler core macros match model",
			property = generated_compiler_core_macros_match_model,
			description = "generated threading, conditional threading, rebinding, mutation setup, and chained value/error binding macros execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated compiler call resolution matches model",
			property = generated_compiler_call_resolution_matches_model,
			description = "generated positional, named, defaulted, generic, global-overload, generic-overload, and local-overload calls execute like an independent model",
			tags = COMPILER_EXPRESSION_TAGS[:],
		},
		{
			name = "generated invalid compiler expressions have bounded diagnostics",
			property = generated_invalid_compiler_expressions_have_bounded_diagnostics,
			description = "generated invalid arities, types, mutations, and removed forms are rejected with category-specific eval diagnostics and bounded spans",
			tags = COMPILER_DIAGNOSTIC_TAGS[:],
		},
	}
	pbt.run_cli(properties[:], os.args[1:], {
		num_tests = 25,
		max_size = 32,
		shrink = true,
	})
}
