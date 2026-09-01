package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Array_Stats :: struct {
	dynamic_literal: int,
	fixed_array:     int,
	empty_literal:   int,
	contains:        int,
	contains_hit:    int,
	contains_miss:   int,
	mutation:        int,
	slice:           int,
	destructure:     int,
}

generated_compiler_array_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Array_Stats
	expected := write_compiler_array_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.dynamic_literal > 0, 3, "dynamic-literal")
	pbt.cover(t, stats.fixed_array > 0, 3, "fixed-array")
	pbt.cover(t, stats.empty_literal > 0, 3, "typed-empty-literal")
	pbt.cover(t, stats.contains > 0, 3, "contains")
	pbt.cover(t, stats.contains_hit > 0, 3, "contains-hit")
	pbt.cover(t, stats.contains_miss > 0, 3, "contains-miss")
	pbt.cover(t, stats.mutation > 0, 3, "mutation")
	pbt.cover(t, stats.slice > 0, 3, "slice")
	pbt.cover(t, stats.destructure > 0, 3, "destructure")

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
			"compiler array expression mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_array_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Array_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 6))
	if kind == 2 {
		stats.empty_literal += 1
		strings.write_string(builder, "(let [xs: [dynamic]int [] :defer] (count xs))")
		return 0
	}

	minimum_length := 3 if kind == 6 else 1
	length := pbt.draw(t, pbt.int_range(minimum_length, 6))
	values: [6]int
	for index in 0 ..< length {
		values[index] = pbt.draw(t, pbt.int_range(-8, 8))
	}

	switch kind {
	case 0:
		stats.dynamic_literal += 1
		index := pbt.draw(t, pbt.int_range(0, length - 1))
		strings.write_string(builder, "(let [xs: [dynamic]int ")
		write_compiler_int_vector(builder, values[:length])
		fmt.sbprintf(builder, " :defer] (+ (* (count xs) 31) (get xs %d)))", index)
		return length * 31 + values[index]
	case 1:
		stats.fixed_array += 1
		index := pbt.draw(t, pbt.int_range(0, length - 1))
		fmt.sbprintf(builder, "(let [xs ([%d]int ", length)
		write_compiler_int_vector(builder, values[:length])
		fmt.sbprintf(builder, ")] (+ (* (count xs) 31) (get xs %d)))", index)
		return length * 31 + values[index]
	case 3:
		stats.contains += 1
		hit := pbt.draw(t, pbt.boolean())
		probe := pbt.draw(t, pbt.int_range(9, 12))
		if hit {
			stats.contains_hit += 1
			probe = values[pbt.draw(t, pbt.int_range(0, length - 1))]
		} else {
			stats.contains_miss += 1
		}
		strings.write_string(builder, "(let [xs: [dynamic]int ")
		write_compiler_int_vector(builder, values[:length])
		fmt.sbprintf(builder, " :defer] (if (contains? xs %d) 1 0))", probe)
		return 1 if hit else 0
	case 4:
		stats.mutation += 1
		index := pbt.draw(t, pbt.int_range(0, length - 1))
		replacement := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [xs: [dynamic]int ")
		write_compiler_int_vector(builder, values[:length])
		fmt.sbprintf(
			builder,
			" :defer before (get xs %d)] (set! (get xs %d) %d) (+ (* before 31) (* (get xs %d) 17) (count xs)))",
			index,
			index,
			replacement,
			index,
		)
		return values[index] * 31 + replacement * 17 + length
	case 5:
		stats.slice += 1
		start := pbt.draw(t, pbt.int_range(0, length - 1))
		end := pbt.draw(t, pbt.int_range(start + 1, length))
		part_length := end - start
		fmt.sbprintf(builder, "(let [xs ([%d]int ", length)
		write_compiler_int_vector(builder, values[:length])
		fmt.sbprintf(
			builder,
			") part (slice xs %d %d)] (+ (* (count part) 31) (* (get part 0) 17) (get part %d)))",
			start,
			end,
			part_length - 1,
		)
		return part_length * 31 + values[start] * 17 + values[end - 1]
	case 6:
		stats.destructure += 1
		fmt.sbprintf(builder, "(let [xs ([%d]int ", length)
		write_compiler_int_vector(builder, values[:length])
		strings.write_string(builder, ") [first second _] xs] (+ (* first 31) (* second 17) (count xs)))")
		return values[0] * 31 + values[1] * 17 + length
	}
	return 0
}

write_compiler_int_vector :: proc(builder: ^strings.Builder, values: []int) {
	strings.write_byte(builder, '[')
	for value, index in values {
		if index > 0 {
			strings.write_byte(builder, ' ')
		}
		fmt.sbprintf(builder, "%d", value)
	}
	strings.write_byte(builder, ']')
}
