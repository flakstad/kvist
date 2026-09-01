package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Call_Stats :: struct {
	positional:       int,
	default_tail:     int,
	pure_named:       int,
	mixed_named:      int,
	reordered_named:  int,
	generic_int:      int,
	generic_bool:     int,
	overload_int:     int,
	overload_bool:    int,
	generic_overload: int,
	local_overload:   int,
}

generated_compiler_call_resolution_matches_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Call_Stats
	expected := write_compiler_call_resolution_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.positional > 0, 3, "positional-call")
	pbt.cover(t, stats.default_tail > 0, 3, "default-tail")
	pbt.cover(t, stats.pure_named > 0, 3, "pure-named-call")
	pbt.cover(t, stats.mixed_named > 0, 3, "mixed-named-call")
	pbt.cover(t, stats.reordered_named > 0, 3, "reordered-named-call")
	pbt.cover(t, stats.generic_int > 0, 3, "generic-int")
	pbt.cover(t, stats.generic_bool > 0, 3, "generic-bool")
	pbt.cover(t, stats.overload_int > 0, 3, "overload-int")
	pbt.cover(t, stats.overload_bool > 0, 3, "overload-bool")
	pbt.cover(t, stats.generic_overload > 0, 3, "generic-overload")
	pbt.cover(t, stats.local_overload > 0, 3, "local-overload")

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
			"compiler call resolution mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_call_resolution_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Call_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 10))
	a := pbt.draw(t, pbt.int_range(-8, 8))
	b := pbt.draw(t, pbt.int_range(-8, 8))
	c := pbt.draw(t, pbt.int_range(-8, 8))
	d := pbt.draw(t, pbt.int_range(-8, 8))

	switch kind {
	case 0:
		stats.positional += 1
		fmt.sbprintf(builder, "(pbt-call-score %d %d %d %d)", a, b, c, d)
		return pbt_call_score_model(a, b, c, d)
	case 1:
		stats.positional += 1
		stats.default_tail += 1
		fmt.sbprintf(builder, "(pbt-call-score %d)", a)
		return pbt_call_score_model(a, 7, 11, 13)
	case 2:
		stats.positional += 1
		stats.default_tail += 1
		fmt.sbprintf(builder, "(pbt-call-score %d %d)", a, b)
		return pbt_call_score_model(a, b, 11, 13)
	case 3:
		stats.pure_named += 1
		stats.reordered_named += 1
		fmt.sbprintf(builder, "(pbt-call-score {{d: %d b: %d a: %d c: %d}})", d, b, a, c)
		return pbt_call_score_model(a, b, c, d)
	case 4:
		stats.pure_named += 1
		stats.default_tail += 1
		fmt.sbprintf(builder, "(pbt-call-score {{a: %d}})", a)
		return pbt_call_score_model(a, 7, 11, 13)
	case 5:
		stats.mixed_named += 1
		stats.reordered_named += 1
		stats.default_tail += 1
		fmt.sbprintf(builder, "(pbt-call-score %d {{c: %d b: %d}})", a, c, b)
		return pbt_call_score_model(a, b, c, 13)
	case 6:
		stats.generic_int += 1
		equal := pbt.draw(t, pbt.boolean())
		expected := a if equal else a + 1
		fmt.sbprintf(builder, "(if (pbt-generic-same? %d %d) 1 0)", a, expected)
		return 1 if equal else 0
	case 7:
		stats.generic_bool += 1
		value := pbt.draw(t, pbt.boolean())
		expected := pbt.draw(t, pbt.boolean())
		fmt.sbprintf(builder, "(if (pbt-generic-same? %t %t) 1 0)", value, expected)
		return 1 if value == expected else 0
	case 8:
		use_bool := pbt.draw(t, pbt.boolean())
		if use_bool {
			stats.overload_bool += 1
			value := pbt.draw(t, pbt.boolean())
			fmt.sbprintf(builder, "(pbt-overload-score %t)", value)
			return 2 if value else 3
		}
		stats.overload_int += 1
		fmt.sbprintf(builder, "(pbt-overload-score %d)", a)
		return a * 31 + 1
	case 9:
		stats.generic_overload += 1
		use_bool := pbt.draw(t, pbt.boolean())
		if use_bool {
			stats.overload_bool += 1
			value := pbt.draw(t, pbt.boolean())
			fmt.sbprintf(builder, "(pbt-generic-overload-score %t)", value)
			return 2 if value else 3
		}
		stats.overload_int += 1
		fmt.sbprintf(builder, "(pbt-generic-overload-score %d)", a)
		return a * 31 + 1
	case 10:
		stats.local_overload += 1
		use_bool := pbt.draw(t, pbt.boolean())
		if use_bool {
			stats.overload_bool += 1
			value := pbt.draw(t, pbt.boolean())
			fmt.sbprintf(builder, "(do (def local-score (overload pbt-overload-int pbt-overload-bool)) (local-score %t))", value)
			return 2 if value else 3
		}
		stats.overload_int += 1
		fmt.sbprintf(builder, "(do (def local-score (overload pbt-overload-int pbt-overload-bool)) (local-score %d))", a)
		return a * 31 + 1
	}
	return 0
}

pbt_call_score_model :: proc(a, b, c, d: int) -> int {
	return a * 31 + b * 17 + c * 7 + d
}
