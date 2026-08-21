// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Multi_Return_Stats :: struct {
	plain_binding:       int,
	discard_first:       int,
	discard_second:      int,
	explicit_ok:         int,
	when_let:            int,
	if_let:              int,
	chained_if_let:      int,
	break_guard:         int,
	continue_guard:      int,
	return_guard:        int,
	sequential_bindings: int,
	optional_fallback:   int,
}

generated_compiler_multi_return_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Multi_Return_Stats
	expected := write_compiler_multi_return_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.plain_binding > 0, 3, "plain-binding")
	pbt.cover(t, stats.discard_first > 0, 3, "discard-first")
	pbt.cover(t, stats.discard_second > 0, 3, "discard-second")
	pbt.cover(t, stats.explicit_ok > 0, 3, "explicit-ok")
	pbt.cover(t, stats.when_let > 0, 3, "when-let")
	pbt.cover(t, stats.if_let > 0, 3, "if-let")
	pbt.cover(t, stats.chained_if_let > 0, 3, "chained-if-let")
	pbt.cover(t, stats.break_guard > 0, 3, "or-break")
	pbt.cover(t, stats.continue_guard > 0, 3, "or-continue")
	pbt.cover(t, stats.return_guard > 0, 3, "or-return")
	pbt.cover(t, stats.sequential_bindings > 0, 3, "sequential-bindings")
	pbt.cover(t, stats.optional_fallback > 0, 3, "or-else")

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
			"compiler multi-return mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_multi_return_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Multi_Return_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 11))
	candidate := pbt.draw(t, pbt.int_range(-12, 12))

	switch kind {
	case 0:
		stats.plain_binding += 1
		denominator := pbt.draw(t, pbt.int_range(1, 6))
		fmt.sbprintf(builder, "(let [[quotient remainder] (pbt-divmod %d %d)] (+ (* quotient 31) remainder))", candidate, denominator)
		return (candidate / denominator) * 31 + candidate % denominator
	case 1:
		stats.discard_first += 1
		denominator := pbt.draw(t, pbt.int_range(1, 6))
		fmt.sbprintf(builder, "(let [[_ remainder] (pbt-divmod %d %d)] remainder)", candidate, denominator)
		return candidate % denominator
	case 2:
		stats.discard_second += 1
		denominator := pbt.draw(t, pbt.int_range(1, 6))
		fmt.sbprintf(builder, "(let [[quotient _] (pbt-divmod %d %d)] quotient)", candidate, denominator)
		return candidate / denominator
	case 3:
		stats.explicit_ok += 1
		stats.optional_fallback += 1
		accepted := pbt.draw(t, pbt.boolean())
		fallback := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [[value ok] (pbt-option %d %t) fallback-value (or-else (pbt-option %d %t) %d)] (+ (* value 2) (if ok 1 0) (* fallback-value 3)))", candidate, accepted, candidate, accepted, fallback)
		optional_value := candidate if accepted else fallback
		return candidate * 2 + (1 if accepted else 0) + optional_value * 3
	case 4:
		stats.when_let += 1
		accepted := pbt.draw(t, pbt.boolean())
		initial := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [total %d] (when-let [[value ok] (pbt-option %d %t)] (set! total (+ total value))) total)", initial, candidate, accepted)
		return initial + candidate if accepted else initial
	case 5:
		stats.if_let += 1
		accepted := pbt.draw(t, pbt.boolean())
		fallback := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(if-let [[value ok] (pbt-option %d %t)] (+ value 10) %d)", candidate, accepted, fallback)
		return candidate + 10 if accepted else fallback
	case 6:
		stats.chained_if_let += 1
		first_ok := pbt.draw(t, pbt.boolean())
		second_ok := pbt.draw(t, pbt.boolean())
		offset := pbt.draw(t, pbt.int_range(-5, 5))
		fallback := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(if-let [[first ok] (pbt-option %d %t) [second ok] (pbt-option (+ first %d) %t)] (+ (* first 7) second) %d)", candidate, first_ok, offset, second_ok, fallback)
		return candidate * 8 + offset if first_ok && second_ok else fallback
	case 7:
		stats.break_guard += 1
		limit := pbt.draw(t, pbt.int_range(1, 8))
		breaks := pbt.draw(t, pbt.boolean())
		fail_at := limit + 1
		if breaks {
			fail_at = pbt.draw(t, pbt.int_range(1, limit))
		}
		fmt.sbprintf(builder, "(let [index 0 total 0] (while (< index %d) (inc! index) (let [[value ok] (pbt-option index (!= index %d)) :or-break] (set! total (+ total value)))) total)", limit, fail_at)
		last := limit
		if breaks {
			last = fail_at - 1
		}
		return last * (last + 1) / 2
	case 8:
		stats.continue_guard += 1
		values, length := draw_compiler_loop_values(t, 1, 6)
		divisor := pbt.draw(t, pbt.int_range(2, 4))
		strings.write_string(builder, "(let [total 0 xs ")
		write_compiler_fixed_int_array(builder, values[:length])
		fmt.sbprintf(builder, "] (for [candidate xs] (let [[value ok] (pbt-option candidate (!= (%% candidate %d) 0)) :or-continue] (set! total (+ total value)))) total)", divisor)
		total := 0
		for value in values[:length] {
			if value % divisor != 0 {
				total += value
			}
		}
		return total
	case 9:
		stats.return_guard += 1
		accepted := pbt.draw(t, pbt.boolean())
		fmt.sbprintf(builder, "(let [[value ok] (pbt-required %d %t)] (+ (* value 2) (if ok 1 0)))", candidate, accepted)
		if accepted {
			return (candidate + 1) * 2 + 1
		}
		return candidate * 2
	case 10:
		stats.sequential_bindings += 1
		first_ok := pbt.draw(t, pbt.boolean())
		second_ok := pbt.draw(t, pbt.boolean())
		offset := pbt.draw(t, pbt.int_range(-5, 5))
		fmt.sbprintf(builder, "(let [[first first-ok] (pbt-option %d %t) [second second-ok] (pbt-option (+ first %d) %t)] (+ first second (if first-ok 10 0) (if second-ok 100 0)))", candidate, first_ok, offset, second_ok)
		return candidate * 2 + offset + (10 if first_ok else 0) + (100 if second_ok else 0)
	case 11:
		stats.optional_fallback += 1
		accepted := pbt.draw(t, pbt.boolean())
		fallback := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(or-else (pbt-option %d %t) %d)", candidate, accepted, fallback)
		return candidate if accepted else fallback
	}
	return 0
}
