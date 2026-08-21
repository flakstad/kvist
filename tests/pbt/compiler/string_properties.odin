// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strings"

import pbt "pbt:pbt"

Compiler_String_Stats :: struct {
	upper:          int,
	lower:          int,
	trim_prefix:    int,
	trim_suffix:    int,
	replace:        int,
	if_form:        int,
	let_form:       int,
	call:           int,
	cond_form:      int,
	case_form:      int,
	escaped_literal: int,
	prefix_hit:     int,
	prefix_miss:    int,
	suffix_hit:     int,
	suffix_miss:    int,
}

generated_compiler_string_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	depth := pbt.draw(t, pbt.int_range(1, 3))
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_String_Stats
	expected := write_compiler_string_expression(t, &builder, depth, &stats, true)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%q", expression, expected))

	pbt.cover(t, stats.upper > 0, 5, "upper")
	pbt.cover(t, stats.lower > 0, 5, "lower")
	pbt.cover(t, stats.trim_prefix > 0, 5, "trim-prefix")
	pbt.cover(t, stats.trim_suffix > 0, 5, "trim-suffix")
	pbt.cover(t, stats.replace > 0, 5, "replace")
	pbt.cover(t, stats.if_form > 0, 5, "if")
	pbt.cover(t, stats.let_form > 0, 5, "let")
	pbt.cover(t, stats.call > 0, 5, "function-call")
	pbt.cover(t, stats.cond_form > 0, 5, "cond")
	pbt.cover(t, stats.case_form > 0, 5, "case")
	pbt.cover(t, stats.escaped_literal > 0, 5, "escaped-literal")
	pbt.cover(t, stats.prefix_hit > 0, 3, "prefix-hit")
	pbt.cover(t, stats.prefix_miss > 0, 3, "prefix-miss")
	pbt.cover(t, stats.suffix_hit > 0, 3, "suffix-hit")
	pbt.cover(t, stats.suffix_miss > 0, 3, "suffix-miss")

	compiler_path := os.get_env("KVIST_PBT_COMPILER", t.value_allocator)
	if compiler_path == "" {
		return pbt.error("KVIST_PBT_COMPILER is not set")
	}
	source_path := os.get_env("KVIST_PBT_COMPILER_STRING_SOURCE", t.value_allocator)
	if source_path == "" {
		return pbt.error("KVIST_PBT_COMPILER_STRING_SOURCE is not set")
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

	actual := strings.trim_space(process.stdout)
	if actual != expected {
		return pbt.fail(fmt.tprintf(
			"compiler string expression mismatch: expected=%q actual=%q expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_string_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	depth: int,
	stats: ^Compiler_String_Stats,
	allow_owned: bool = false,
) -> string {
	if depth <= 0 {
		return write_compiler_string_literal(t, builder, stats)
	}

	kind := pbt.draw(t, pbt.int_range(0, 10))
	if !allow_owned {
		borrowed_kinds := [?]int{0, 3, 4, 6, 7, 8, 9, 10}
		kind = borrowed_kinds[pbt.draw(t, pbt.int_range(0, len(borrowed_kinds) - 1))]
	}
	switch kind {
	case 0:
		return write_compiler_string_literal(t, builder, stats)
	case 1:
		stats.upper += 1
		strings.write_string(builder, "(str.upper ")
		value := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		result, _ := strings.to_upper(value, t.value_allocator)
		return result
	case 2:
		stats.lower += 1
		strings.write_string(builder, "(str.lower ")
		value := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		result, _ := strings.to_lower(value, t.value_allocator)
		return result
	case 3:
		stats.trim_prefix += 1
		strings.write_string(builder, "(str.trim-prefix ")
		value := write_compiler_string_expression(t, builder, depth - 1, stats)
		prefix := compiler_string_affix(t, value, true, stats)
		strings.write_byte(builder, ' ')
		write_compiler_quoted_string(builder, prefix)
		strings.write_byte(builder, ')')
		if strings.has_prefix(value, prefix) {
			return value[len(prefix):]
		}
		return value
	case 4:
		stats.trim_suffix += 1
		strings.write_string(builder, "(str.trim-suffix ")
		value := write_compiler_string_expression(t, builder, depth - 1, stats)
		suffix := compiler_string_affix(t, value, false, stats)
		strings.write_byte(builder, ' ')
		write_compiler_quoted_string(builder, suffix)
		strings.write_byte(builder, ')')
		if strings.has_suffix(value, suffix) {
			return value[:len(value) - len(suffix)]
		}
		return value
	case 5:
		stats.replace += 1
		old := pbt.draw(t, pbt.string_alphabet("abXY", 1, 1))
		new := pbt.draw(t, pbt.string_alphabet("pq09", 0, 2))
		strings.write_string(builder, "(str.replace ")
		value := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		write_compiler_quoted_string(builder, old)
		strings.write_byte(builder, ' ')
		write_compiler_quoted_string(builder, new)
		strings.write_byte(builder, ')')
		result, _ := strings.replace(value, old, new, -1, t.value_allocator)
		return result
	case 6:
		stats.if_form += 1
		bool_stats: Compiler_Bool_Stats
		strings.write_string(builder, "(if (identity-bool ")
		condition := write_compiler_boolean_expression(t, builder, depth - 1, &bool_stats)
		strings.write_string(builder, ") ")
		when_true := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		when_false := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return when_true if condition else when_false
	case 7:
		stats.let_form += 1
		strings.write_string(builder, "(let [x ")
		value := write_compiler_string_expression(t, builder, depth - 1, stats)
		prefix := compiler_string_affix(t, value, true, stats)
		strings.write_string(builder, " result: string (str.trim-prefix x ")
		write_compiler_quoted_string(builder, prefix)
		strings.write_string(builder, ")] result)")
		stats.trim_prefix += 1
		if strings.has_prefix(value, prefix) {
			return value[len(prefix):]
		}
		return value
	case 8:
		stats.call += 1
		bool_stats: Compiler_Bool_Stats
		strings.write_string(builder, "(choose-text ")
		condition := write_compiler_boolean_expression(t, builder, depth - 1, &bool_stats)
		strings.write_byte(builder, ' ')
		when_true := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		when_false := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return when_true if condition else when_false
	case 9:
		stats.cond_form += 1
		bool_stats: Compiler_Bool_Stats
		strings.write_string(builder, "(cond (identity-bool ")
		condition := write_compiler_boolean_expression(t, builder, depth - 1, &bool_stats)
		strings.write_string(builder, ") ")
		when_true := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_string(builder, " :else ")
		when_false := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return when_true if condition else when_false
	case 10:
		stats.case_form += 1
		match := pbt.draw(t, pbt.int_range(-3, 3))
		int_stats: Compiler_Expression_Stats
		strings.write_string(builder, "(case ")
		value := write_compiler_expression(t, builder, depth - 1, &int_stats)
		fmt.sbprintf(builder, " %d ", match)
		when_match := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ' ')
		fallback := write_compiler_string_expression(t, builder, depth - 1, stats)
		strings.write_byte(builder, ')')
		return when_match if value == match else fallback
	}
	return ""
}

write_compiler_string_literal :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_String_Stats,
) -> string {
	value := pbt.draw(t, pbt.string_alphabet("abXY09_-\\\"", 0, 6))
	if strings.contains(value, "\\") || strings.contains(value, "\"") {
		stats.escaped_literal += 1
	}
	write_compiler_quoted_string(builder, value)
	return value
}

write_compiler_quoted_string :: proc(builder: ^strings.Builder, value: string) {
	strings.write_byte(builder, '"')
	for character in value {
		if character == '\\' || character == '"' {
			strings.write_byte(builder, '\\')
		}
		strings.write_rune(builder, character)
	}
	strings.write_byte(builder, '"')
}

compiler_string_affix :: proc(
	t: ^pbt.T,
	value: string,
	prefix: bool,
	stats: ^Compiler_String_Stats,
) -> string {
	want_hit := len(value) > 0 && pbt.draw(t, pbt.boolean())
	if want_hit {
		if prefix {
			stats.prefix_hit += 1
			return value[:1]
		}
		stats.suffix_hit += 1
		return value[len(value) - 1:]
	}
	if prefix {
		stats.prefix_miss += 1
	} else {
		stats.suffix_miss += 1
	}
	return "Q"
}
