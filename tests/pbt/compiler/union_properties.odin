package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Union_Stats :: struct {
	raw_payload:     int,
	single_payload:  int,
	pair_payload:    int,
	direct_score:    int,
	type_case:       int,
	ignored_payload: int,
	typed_branch:    int,
	nested_struct:   int,
	assoc:           int,
	mutation:        int,
	do_arm:          int,
	copy:            int,
	array:           int,
}

generated_compiler_union_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Union_Stats
	expected := write_compiler_union_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.raw_payload > 0, 3, "raw-payload")
	pbt.cover(t, stats.single_payload > 0, 3, "single-payload")
	pbt.cover(t, stats.pair_payload > 0, 3, "pair-payload")
	pbt.cover(t, stats.direct_score > 0, 3, "direct-score")
	pbt.cover(t, stats.type_case > 0, 3, "type-case")
	pbt.cover(t, stats.ignored_payload > 0, 3, "ignored-payload")
	pbt.cover(t, stats.typed_branch > 0, 3, "typed-branch")
	pbt.cover(t, stats.nested_struct > 0, 3, "nested-struct")
	pbt.cover(t, stats.assoc > 0, 3, "assoc")
	pbt.cover(t, stats.mutation > 0, 3, "mutation")
	pbt.cover(t, stats.do_arm > 0, 3, "do-arm")
	pbt.cover(t, stats.copy > 0, 3, "copy")
	pbt.cover(t, stats.array > 0, 3, "array")

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
			"compiler union expression mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_union_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Union_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 9))
	variant := pbt.draw(t, pbt.int_range(0, 2))
	first := pbt.draw(t, pbt.int_range(-8, 8))
	second := pbt.draw(t, pbt.int_range(-8, 8))
	score := compiler_union_score(variant, first, second)

	switch kind {
	case 0:
		stats.direct_score += 1
		strings.write_string(builder, "(pbt-value-score ")
		write_compiler_union_value(builder, stats, variant, first, second)
		strings.write_byte(builder, ')')
		return score
	case 1:
		stats.type_case += 1
		strings.write_string(builder, "(let [result: int (case ")
		write_compiler_union_value(builder, stats, variant, first, second)
		strings.write_string(builder, " (Pbt-Single item) (+ item.value 101) (Pbt-Pair item) (+ (* item.left 10) item.right 202) (int raw) (+ raw 303) -1)] result)")
		switch variant {
		case 0:
			return first + 303
		case 1:
			return first + 101
		case 2:
			return first * 10 + second + 202
		}
	case 2:
		stats.ignored_payload += 1
		strings.write_string(builder, "(let [result: int (case ")
		write_compiler_union_value(builder, stats, variant, first, second)
		strings.write_string(builder, " (Pbt-Single _) 17 (Pbt-Pair _) 23 (int _) 31 -1)] result)")
		switch variant {
		case 0:
			return 31
		case 1:
			return 17
		case 2:
			return 23
		}
	case 3:
		stats.typed_branch += 1
		condition := pbt.draw(t, pbt.boolean())
		other_variant := pbt.draw(t, pbt.int_range(0, 2))
		other_first := pbt.draw(t, pbt.int_range(-8, 8))
		other_second := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [value: Pbt-Value (if (identity-bool %t) ", condition)
		write_compiler_union_value(builder, stats, variant, first, second)
		strings.write_byte(builder, ' ')
		write_compiler_union_value(builder, stats, other_variant, other_first, other_second)
		strings.write_string(builder, ")] (pbt-value-score value))")
		return score if condition else compiler_union_score(other_variant, other_first, other_second)
	case 4:
		stats.nested_struct += 1
		bias := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(pbt-envelope-score (Pbt-Envelope {value: ")
		write_compiler_union_value(builder, stats, variant, first, second)
		fmt.sbprintf(builder, " bias: %d}))", bias)
		return score * 13 + bias
	case 5:
		stats.assoc += 1
		bias := pbt.draw(t, pbt.int_range(-8, 8))
		other_variant := pbt.draw(t, pbt.int_range(0, 2))
		other_first := pbt.draw(t, pbt.int_range(-8, 8))
		other_second := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [original (Pbt-Envelope {value: ")
		write_compiler_union_value(builder, stats, variant, first, second)
		fmt.sbprintf(builder, " bias: %d}) newer (assoc original.value ", bias)
		write_compiler_union_value(builder, stats, other_variant, other_first, other_second)
		strings.write_string(builder, ")] (+ (pbt-envelope-score original) (pbt-envelope-score newer)))")
		return (score + compiler_union_score(other_variant, other_first, other_second)) * 13 + bias * 2
	case 6:
		stats.mutation += 1
		other_variant := pbt.draw(t, pbt.int_range(0, 2))
		other_first := pbt.draw(t, pbt.int_range(-8, 8))
		other_second := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [value ")
		write_compiler_union_value(builder, stats, variant, first, second)
		strings.write_string(builder, "] (set! value ")
		write_compiler_union_value(builder, stats, other_variant, other_first, other_second)
		strings.write_string(builder, ") (pbt-value-score value))")
		return compiler_union_score(other_variant, other_first, other_second)
	case 7:
		stats.do_arm += 1
		strings.write_string(builder, "(let [result: int (case ")
		write_compiler_union_value(builder, stats, variant, first, second)
		strings.write_string(builder, " (Pbt-Single item) (do (+ (* item.value 2) 1)) (Pbt-Pair item) (do (+ item.left item.right 2)) (int raw) (do (- raw 3)) -1)] result)")
		switch variant {
		case 0:
			return first - 3
		case 1:
			return first * 2 + 1
		case 2:
			return first + second + 2
		}
	case 8:
		stats.copy += 1
		strings.write_string(builder, "(let [original ")
		write_compiler_union_value(builder, stats, variant, first, second)
		strings.write_string(builder, " copy original] (+ (* (pbt-value-score original) 5) (pbt-value-score copy)))")
		return score * 6
	case 9:
		stats.array += 1
		other_variant := pbt.draw(t, pbt.int_range(0, 2))
		other_first := pbt.draw(t, pbt.int_range(-8, 8))
		other_second := pbt.draw(t, pbt.int_range(-8, 8))
		index := pbt.draw(t, pbt.int_range(0, 1))
		strings.write_string(builder, "(let [values ([2]Pbt-Value [")
		write_compiler_union_value(builder, stats, variant, first, second)
		strings.write_byte(builder, ' ')
		write_compiler_union_value(builder, stats, other_variant, other_first, other_second)
		fmt.sbprintf(builder, "])] (pbt-value-score (get values %d)))", index)
		return score if index == 0 else compiler_union_score(other_variant, other_first, other_second)
	}
	return 0
}

write_compiler_union_value :: proc(
	builder: ^strings.Builder,
	stats: ^Compiler_Union_Stats,
	variant, first, second: int,
) {
	switch variant {
	case 0:
		stats.raw_payload += 1
		strings.write_string(builder, "(Pbt-Value {raw: ")
		fmt.sbprintf(builder, "%d})", first)
	case 1:
		stats.single_payload += 1
		strings.write_string(builder, "(Pbt-Value {single: (Pbt-Single {value: ")
		fmt.sbprintf(builder, "%d})})", first)
	case 2:
		stats.pair_payload += 1
		strings.write_string(builder, "(Pbt-Value {pair: (Pbt-Pair {left: ")
		fmt.sbprintf(builder, "%d right: %d})})", first, second)
	}
}

compiler_union_score :: proc(variant, first, second: int) -> int {
	switch variant {
	case 0:
		return first * 3 + 3
	case 1:
		return first * 11 + 1
	case 2:
		return first * 7 + second * 5 + 2
	}
	return -999
}
