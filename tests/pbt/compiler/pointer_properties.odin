// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Pointer_Stats :: struct {
	address_form:      int,
	address_suffix:    int,
	deref_form:        int,
	deref_suffix:      int,
	pointee_set:       int,
	pointee_mut:       int,
	aliasing:          int,
	function_boundary: int,
	struct_pointer:    int,
	field_pointer:     int,
	array_pointer:     int,
	pointer_choice:    int,
	pointer_to_pointer: int,
}

generated_compiler_pointer_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Pointer_Stats
	expected := write_compiler_pointer_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.address_form > 0, 3, "address-form")
	pbt.cover(t, stats.address_suffix > 0, 3, "address-suffix")
	pbt.cover(t, stats.deref_form > 0, 3, "deref-form")
	pbt.cover(t, stats.deref_suffix > 0, 3, "deref-suffix")
	pbt.cover(t, stats.pointee_set > 0, 3, "pointee-set")
	pbt.cover(t, stats.pointee_mut > 0, 3, "pointee-mut")
	pbt.cover(t, stats.aliasing > 0, 3, "aliasing")
	pbt.cover(t, stats.function_boundary > 0, 3, "function-boundary")
	pbt.cover(t, stats.struct_pointer > 0, 3, "struct-pointer")
	pbt.cover(t, stats.field_pointer > 0, 3, "field-pointer")
	pbt.cover(t, stats.array_pointer > 0, 3, "array-pointer")
	pbt.cover(t, stats.pointer_choice > 0, 3, "pointer-choice")
	pbt.cover(t, stats.pointer_to_pointer > 0, 3, "pointer-to-pointer")

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
			"compiler pointer mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_pointer_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Pointer_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 12))
	value := pbt.draw(t, pbt.int_range(-8, 8))

	switch kind {
	case 0:
		stats.address_form += 1
		stats.deref_form += 1
		fmt.sbprintf(builder, "(let [value %d pointer (addr value)] (deref pointer))", value)
		return value
	case 1:
		stats.address_suffix += 1
		stats.deref_suffix += 1
		fmt.sbprintf(builder, "(let [value %d pointer &value] pointer^)", value)
		return value
	case 2:
		stats.address_form += 1
		stats.deref_form += 1
		stats.pointee_set += 1
		replacement := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [value %d pointer (addr value)] (set! (deref pointer) %d) value)", value, replacement)
		return replacement
	case 3:
		stats.address_suffix += 1
		stats.deref_suffix += 1
		stats.pointee_mut += 1
		delta := pbt.draw(t, pbt.int_range(-5, 5))
		fmt.sbprintf(builder, "(let [value %d pointer &value] (mut! pointer^ += %d) value)", value, delta)
		return value + delta
	case 4:
		stats.address_form += 1
		stats.deref_suffix += 1
		stats.aliasing += 1
		stats.pointee_set += 1
		replacement := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [value %d pointer (addr value) alias pointer] (set! alias^ %d) (+ value pointer^))", value, replacement)
		return replacement * 2
	case 5:
		stats.address_form += 1
		stats.deref_suffix += 1
		stats.function_boundary += 1
		stats.pointee_mut += 1
		delta := pbt.draw(t, pbt.int_range(-5, 5))
		fmt.sbprintf(builder, "(let [value %d result (pbt-add-through-pointer! (addr value) %d)] (+ (* value 31) result))", value, delta)
		updated := value + delta
		return updated * 32
	case 6:
		stats.address_form += 1
		stats.deref_suffix += 1
		stats.struct_pointer += 1
		x := pbt.draw(t, pbt.int_range(-5, 5))
		y := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(let [point (Pbt-Point {x: ")
		fmt.sbprintf(builder, "%d y: %d weight: %d active?: false}) pointer (addr point)] (+ (* pointer^.x 31) (* pointer^.y 17) pointer^.weight))", x, y, value)
		return x * 31 + y * 17 + value
	case 7:
		stats.address_form += 1
		stats.deref_suffix += 1
		stats.struct_pointer += 1
		stats.pointee_set += 1
		x := pbt.draw(t, pbt.int_range(-5, 5))
		y := pbt.draw(t, pbt.int_range(-5, 5))
		replacement := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(let [point (Pbt-Point {x: ")
		fmt.sbprintf(builder, "%d y: %d weight: 0 active?: false}) pointer (addr point)] (set! pointer^.y %d) (+ (* point.x 31) point.y))", x, y, replacement)
		return x * 31 + replacement
	case 8:
		stats.address_form += 1
		stats.deref_suffix += 1
		stats.field_pointer += 1
		stats.function_boundary += 1
		x := pbt.draw(t, pbt.int_range(-5, 5))
		delta := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(let [point (Pbt-Point {x: ")
		fmt.sbprintf(builder, "%d y: %d weight: 0 active?: false}) result (pbt-add-through-pointer! (addr point.x) %d)] (+ (* point.x 31) result))", x, value, delta)
		updated := x + delta
		return updated * 32
	case 9:
		stats.address_form += 1
		stats.deref_form += 1
		stats.array_pointer += 1
		stats.pointee_set += 1
		values, length := draw_compiler_loop_values(t, 2, 6)
		index := pbt.draw(t, pbt.int_range(0, length - 1))
		replacement := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [values ")
		write_compiler_fixed_int_array(builder, values[:length])
		fmt.sbprintf(builder, " pointer (addr values)] (set! (deref pointer)[%d] %d) (+ (* (get values %d) 31) (count values)))", index, replacement, index)
		return replacement * 31 + length
	case 10:
		stats.address_form += 1
		stats.deref_suffix += 1
		stats.array_pointer += 1
		stats.function_boundary += 1
		stats.pointee_mut += 1
		values, length := draw_compiler_loop_values(t, 2, 6)
		index := pbt.draw(t, pbt.int_range(0, length - 1))
		delta := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(let [values ")
		write_compiler_fixed_int_array(builder, values[:length])
		fmt.sbprintf(builder, " cell (pbt-cell-pointer (slice values 0) %d)] (mut! cell^ += %d) (+ (* (get values %d) 31) cell^))", index, delta, index)
		updated := values[index] + delta
		return updated * 32
	case 11:
		stats.address_form += 1
		stats.deref_suffix += 1
		stats.pointer_choice += 1
		stats.aliasing += 1
		left := pbt.draw(t, pbt.int_range(-8, 8))
		right := pbt.draw(t, pbt.int_range(-8, 8))
		choose_left := pbt.draw(t, pbt.boolean())
		replacement := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [left %d right %d pointer (if %t (addr left) (addr right))] (set! pointer^ %d) (+ (* left 31) right))", left, right, choose_left, replacement)
		return replacement * 31 + right if choose_left else left * 31 + replacement
	case 12:
		stats.address_form += 1
		stats.deref_form += 1
		stats.deref_suffix += 1
		stats.pointer_to_pointer += 1
		stats.aliasing += 1
		replacement := pbt.draw(t, pbt.int_range(-8, 8))
		fmt.sbprintf(builder, "(let [value %d pointer (addr value) outer (addr pointer)] (set! (deref (deref outer)) %d) (+ value pointer^))", value, replacement)
		return replacement * 2
	}
	return 0
}
