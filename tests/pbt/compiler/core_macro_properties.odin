package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Core_Macro_Stats :: struct {
	thread_last: int,
	cond_thread: int,
	as_thread:   int,
	doto:        int,
	when_let:    int,
	if_let:      int,
	when_ok:     int,
	if_ok:       int,
	short_stop:  int,
	eval_once:   int,
}

generated_compiler_core_macros_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Core_Macro_Stats
	expected := write_compiler_core_macro_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.thread_last > 0, 3, "thread-last")
	pbt.cover(t, stats.cond_thread > 0, 3, "conditional-thread")
	pbt.cover(t, stats.as_thread > 0, 3, "as-thread")
	pbt.cover(t, stats.doto > 0, 3, "doto")
	pbt.cover(t, stats.when_let > 0, 3, "when-let")
	pbt.cover(t, stats.if_let > 0, 3, "if-let")
	pbt.cover(t, stats.when_ok > 0, 3, "when-ok")
	pbt.cover(t, stats.if_ok > 0, 3, "if-ok")
	pbt.cover(t, stats.short_stop > 0, 10, "binding-short-circuit")
	pbt.cover(t, stats.eval_once > 0, 20, "single-evaluation")

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
			"compiler core macro mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_core_macro_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Core_Macro_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 7))
	value := pbt.draw(t, pbt.int_range(-8, 8))
	a := pbt.draw(t, pbt.int_range(-5, 5))
	b := pbt.draw(t, pbt.int_range(-5, 5))

	switch kind {
	case 0:
		stats.thread_last += 1
		scale := pbt.draw(t, pbt.int_range(-3, 3))
		strings.write_string(builder, "(->> ")
		fmt.sbprintf(builder, "%d (pbt-last-affine %d %d) (pbt-last-affine %d %d))", value, scale, a, b, scale)
		return ((value * scale + a) * b + scale)
	case 1:
		stats.cond_thread += 1
		stats.eval_once += 1
		first := pbt.draw(t, pbt.boolean())
		second := pbt.draw(t, pbt.boolean())
		calls := 1
		result := value
		if first {
			result += a
		}
		if second {
			result *= b
		}
		fmt.sbprintf(builder, "(let [result (cond-> (pbt-counted-int %d) (pbt-counted-bool %t) (+ %d) (pbt-counted-bool %t) (* %d))] (+ (* result 10) pbt-macro-calls))", value, first, a, second, b)
		return result * 10 + calls + 2
	case 2:
		stats.as_thread += 1
		stats.eval_once += 1
		fmt.sbprintf(builder, "(let [result: int (as-> (pbt-counted-int %d) x (+ x %d) (* %d x) (- x %d))] (+ (* result 10) pbt-macro-calls))", value, a, b, a)
		return (((value + a) * b) - a) * 10 + 1
	case 3:
		stats.doto += 1
		stats.eval_once += 1
		fmt.sbprintf(builder, "(let [result (doto (pbt-counted-pointer %d) (pbt-add-through-pointer! %d) (pbt-add-through-pointer! %d))] (+ (* result^ 10) pbt-macro-calls))", value, a, b)
		return (value + a + b) * 10 + 1
	case 4, 5, 6, 7:
		first_ok := pbt.draw(t, pbt.boolean())
		second_ok := pbt.draw(t, pbt.boolean())
		calls := 1
		if first_ok {
			calls += 1
		} else {
			stats.short_stop += 1
		}
		if first_ok && !second_ok {
			stats.short_stop += 1
		}
		success := first_ok && second_ok
		if kind == 4 {
			stats.when_let += 1
			fmt.sbprintf(builder, "(let [total %d] (when-let [[x ok-x] (pbt-counted-option %d %t) [y ok-y] (pbt-counted-option %d %t)] (set! total (+ x y))) (+ (* total 10) pbt-macro-calls))", b, value, first_ok, a, second_ok)
			return ((value + a) if success else b) * 10 + calls
		}
		if kind == 5 {
			stats.if_let += 1
			fmt.sbprintf(builder, "(let [result: int (if-let [[x ok-x] (pbt-counted-option %d %t) [y ok-y] (pbt-counted-option %d %t)] (+ x y) %d)] (+ (* result 10) pbt-macro-calls))", value, first_ok, a, second_ok, b)
			return ((value + a) if success else b) * 10 + calls
		}
		if kind == 6 {
			stats.when_ok += 1
			fmt.sbprintf(builder, "(let [total %d] (when-ok [[x err-x] (pbt-counted-error %d %t) [y err-y] (pbt-counted-error %d %t)] (set! total (+ x y))) (+ (* total 10) pbt-macro-calls))", b, value, first_ok, a, second_ok)
			return ((value + a) if success else b) * 10 + calls
		}
		stats.if_ok += 1
		fmt.sbprintf(builder, "(let [result: int (if-ok [[x err-x] (pbt-counted-error %d %t) [y err-y] (pbt-counted-error %d %t)] (+ x y) %d)] (+ (* result 10) pbt-macro-calls))", value, first_ok, a, second_ok, b)
		return ((value + a) if success else b) * 10 + calls
	}
	return 0
}
