package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Control_Flow_Stats :: struct {
	for_value:          int,
	for_index:          int,
	for_continue:       int,
	for_break:          int,
	for_continue_break: int,
	while_condition:    int,
	while_continue:     int,
	while_break:        int,
	nested_for:         int,
	empty_for:          int,
}

generated_compiler_control_flow_matches_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Control_Flow_Stats
	expected := write_compiler_control_flow_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.for_value > 0, 3, "for-value")
	pbt.cover(t, stats.for_index > 0, 3, "for-index")
	pbt.cover(t, stats.for_continue > 0, 3, "for-continue")
	pbt.cover(t, stats.for_break > 0, 3, "for-break")
	pbt.cover(t, stats.for_continue_break > 0, 3, "for-continue-break")
	pbt.cover(t, stats.while_condition > 0, 3, "while-condition")
	pbt.cover(t, stats.while_continue > 0, 3, "while-continue")
	pbt.cover(t, stats.while_break > 0, 3, "while-break")
	pbt.cover(t, stats.nested_for > 0, 3, "nested-for")
	pbt.cover(t, stats.empty_for > 0, 3, "empty-for")

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
			"compiler control-flow mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_control_flow_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Control_Flow_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 9))

	switch kind {
	case 0:
		stats.for_value += 1
		values, length := draw_compiler_loop_values(t, 1, 6)
		strings.write_string(builder, "(let [total 0 xs ")
		write_compiler_fixed_int_array(builder, values[:length])
		strings.write_string(builder, "] (for [value xs] (set! total (+ total value))) total)")
		return compiler_loop_sum(values[:length])
	case 1:
		stats.for_index += 1
		values, length := draw_compiler_loop_values(t, 1, 6)
		strings.write_string(builder, "(let [total 0 xs ")
		write_compiler_fixed_int_array(builder, values[:length])
		strings.write_string(builder, "] (for [value index xs] (set! total (+ total (* value 10) index))) total)")
		total := 0
		for value, index in values[:length] {
			total += value * 10 + index
		}
		return total
	case 2:
		stats.for_continue += 1
		values, length := draw_compiler_loop_values(t, 1, 6)
		divisor := pbt.draw(t, pbt.int_range(2, 4))
		strings.write_string(builder, "(let [total 0 xs ")
		write_compiler_fixed_int_array(builder, values[:length])
		fmt.sbprintf(builder, "] (for [value xs] (when (= (%% value %d) 0) (continue)) (set! total (+ total value))) total)", divisor)
		total := 0
		for value in values[:length] {
			if value % divisor != 0 {
				total += value
			}
		}
		return total
	case 3:
		stats.for_break += 1
		values, length := draw_compiler_loop_values(t, 1, 6)
		threshold := pbt.draw(t, pbt.int_range(-4, 4))
		strings.write_string(builder, "(let [total 0 xs ")
		write_compiler_fixed_int_array(builder, values[:length])
		fmt.sbprintf(builder, "] (for [value xs] (when (> value %d) (break)) (set! total (+ total value))) total)", threshold)
		total := 0
		for value in values[:length] {
			if value > threshold {
				break
			}
			total += value
		}
		return total
	case 4:
		stats.for_continue_break += 1
		values, length := draw_compiler_loop_values(t, 1, 6)
		skip_below := pbt.draw(t, pbt.int_range(-5, -1))
		break_above := pbt.draw(t, pbt.int_range(1, 5))
		strings.write_string(builder, "(let [total 0 xs ")
		write_compiler_fixed_int_array(builder, values[:length])
		fmt.sbprintf(builder, "] (for [value xs] (when (< value %d) (continue)) (when (> value %d) (break)) (set! total (+ total value))) total)", skip_below, break_above)
		total := 0
		for value in values[:length] {
			if value < skip_below {
				continue
			}
			if value > break_above {
				break
			}
			total += value
		}
		return total
	case 5:
		stats.while_condition += 1
		limit := pbt.draw(t, pbt.int_range(0, 8))
		offset := pbt.draw(t, pbt.int_range(-3, 3))
		fmt.sbprintf(builder, "(let [i 0 total 0] (while (< i %d) (set! total (+ total i %d)) (inc! i)) total)", limit, offset)
		total := 0
		for i in 0 ..< limit {
			total += i + offset
		}
		return total
	case 6:
		stats.while_continue += 1
		limit := pbt.draw(t, pbt.int_range(0, 8))
		divisor := pbt.draw(t, pbt.int_range(2, 4))
		fmt.sbprintf(builder, "(let [i 0 total 0] (while (< i %d) (inc! i) (when (= (%% i %d) 0) (continue)) (set! total (+ total i))) total)", limit, divisor)
		total := 0
		for i in 1 ..= limit {
			if i % divisor != 0 {
				total += i
			}
		}
		return total
	case 7:
		stats.while_break += 1
		stop := pbt.draw(t, pbt.int_range(0, 8))
		fmt.sbprintf(builder, "(let [i 0 total 0] (while true (when (= i %d) (break)) (set! total (+ total i)) (inc! i)) total)", stop)
		total := 0
		for i in 0 ..< stop {
			total += i
		}
		return total
	case 8:
		stats.nested_for += 1
		left, left_length := draw_compiler_loop_values(t, 1, 4)
		right, right_length := draw_compiler_loop_values(t, 1, 4)
		strings.write_string(builder, "(let [total 0 xs ")
		write_compiler_fixed_int_array(builder, left[:left_length])
		strings.write_string(builder, " ys ")
		write_compiler_fixed_int_array(builder, right[:right_length])
		strings.write_string(builder, "] (for [x xs] (for [y ys] (set! total (+ total (* x y))))) total)")
		total := 0
		for x in left[:left_length] {
			for y in right[:right_length] {
				total += x * y
			}
		}
		return total
	case 9:
		stats.empty_for += 1
		initial := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [total %d xs ([0]int [])] (for [value xs] (set! total (+ total value))) total)", initial)
		return initial
	}
	return 0
}

draw_compiler_loop_values :: proc(t: ^pbt.T, minimum_length, maximum_length: int) -> ([6]int, int) {
	values: [6]int
	length := pbt.draw(t, pbt.int_range(minimum_length, maximum_length))
	for index in 0 ..< length {
		values[index] = pbt.draw(t, pbt.int_range(-8, 8))
	}
	return values, length
}

write_compiler_fixed_int_array :: proc(builder: ^strings.Builder, values: []int) {
	fmt.sbprintf(builder, "([%d]int ", len(values))
	write_compiler_int_vector(builder, values)
	strings.write_byte(builder, ')')
}

compiler_loop_sum :: proc(values: []int) -> int {
	total := 0
	for value in values {
		total += value
	}
	return total
}
