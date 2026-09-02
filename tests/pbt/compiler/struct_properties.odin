package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Point_Model :: struct {
	x:      int,
	y:      int,
	weight: int,
	active: bool,
}

Compiler_Struct_Stats :: struct {
	full_literal:  int,
	omitted_fields: int,
	copy_mutation: int,
	assoc:         int,
	update:        int,
	nested_assoc:  int,
	nested_update: int,
	in_place:      int,
	unary:         int,
	branch:        int,
}

generated_compiler_struct_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Struct_Stats
	expected := write_compiler_struct_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.full_literal > 0, 3, "full-literal")
	pbt.cover(t, stats.omitted_fields > 0, 3, "omitted-fields")
	pbt.cover(t, stats.copy_mutation > 0, 3, "copy-mutation")
	pbt.cover(t, stats.assoc > 0, 3, "assoc")
	pbt.cover(t, stats.update > 0, 3, "update")
	pbt.cover(t, stats.nested_assoc > 0, 3, "nested-assoc")
	pbt.cover(t, stats.nested_update > 0, 3, "nested-update")
	pbt.cover(t, stats.in_place > 0, 3, "update-bang")
	pbt.cover(t, stats.unary > 0, 3, "unary-mutation")
	pbt.cover(t, stats.branch > 0, 3, "branch")

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
			"compiler struct expression mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_struct_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Struct_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 9))
	point := generated_compiler_point(t)

	switch kind {
	case 0:
		stats.full_literal += 1
		strings.write_string(builder, "(pbt-point-score ")
		write_compiler_point_literal(builder, point)
		strings.write_byte(builder, ')')
		return compiler_point_score(point)
	case 1:
		stats.omitted_fields += 1
		strings.write_string(builder, "(pbt-point-score (Pbt-Point :x ")
		fmt.sbprintf(builder, "%d", point.x)
		strings.write_string(builder, "))")
		return point.x * 31
	case 2:
		stats.copy_mutation += 1
		new_y := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [original ")
		write_compiler_point_literal(builder, point)
		fmt.sbprintf(
			builder,
			" copy original] (set! copy.y %d) (+ (* (pbt-point-score original) 7) (pbt-point-score copy)))",
			new_y,
		)
		copy := point
		copy.y = new_y
		return compiler_point_score(point) * 7 + compiler_point_score(copy)
	case 3:
		stats.assoc += 1
		new_weight := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [original ")
		write_compiler_point_literal(builder, point)
		fmt.sbprintf(
			builder,
			" newer (assoc original.weight %d)] (+ (* (pbt-point-score original) 7) (pbt-point-score newer)))",
			new_weight,
		)
		newer := point
		newer.weight = new_weight
		return compiler_point_score(point) * 7 + compiler_point_score(newer)
	case 4:
		stats.update += 1
		delta := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(let [original ")
		write_compiler_point_literal(builder, point)
		fmt.sbprintf(
			builder,
			" newer (update original.y + %d)] (+ (* (pbt-point-score original) 7) (pbt-point-score newer)))",
			delta,
		)
		newer := point
		newer.y += delta
		return compiler_point_score(point) * 7 + compiler_point_score(newer)
	case 5:
		stats.nested_assoc += 1
		bias := pbt.draw(t, pbt.int_range(-8, 8))
		new_x := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [original (Pbt-Box :point ")
		write_compiler_point_literal(builder, point)
		fmt.sbprintf(
			builder,
			" :bias %d) newer (assoc original.point.x %d)] (+ (* (pbt-box-score original) 7) (pbt-box-score newer)))",
			bias,
			new_x,
		)
		newer := point
		newer.x = new_x
		return (compiler_point_score(point) * 7 + bias) * 7 + compiler_point_score(newer) * 7 + bias
	case 6:
		stats.nested_update += 1
		bias := pbt.draw(t, pbt.int_range(-8, 8))
		delta := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(let [original (Pbt-Box :point ")
		write_compiler_point_literal(builder, point)
		fmt.sbprintf(builder, " :bias %d) newer (update original.point.weight + %d)] (pbt-box-score newer))", bias, delta)
		point.weight += delta
		return compiler_point_score(point) * 7 + bias
	case 7:
		stats.in_place += 1
		delta := pbt.draw(t, pbt.int_range(-5, 5))
		strings.write_string(builder, "(let [point ")
		write_compiler_point_literal(builder, point)
		fmt.sbprintf(builder, "] (update! point.y + %d) (pbt-point-score point))", delta)
		point.y += delta
		return compiler_point_score(point)
	case 8:
		stats.unary += 1
		strings.write_string(builder, "(let [point ")
		write_compiler_point_literal(builder, point)
		strings.write_string(builder, "] (inc! point.x) (dec! point.weight) (negate! point.y) (toggle! point.active?) (pbt-point-score point))")
		point.x += 1
		point.weight -= 1
		point.y = -point.y
		point.active = !point.active
		return compiler_point_score(point)
	case 9:
		stats.branch += 1
		condition := pbt.draw(t, pbt.boolean())
		other := generated_compiler_point(t)
		fmt.sbprintf(builder, "(let [point: Pbt-Point (if (identity-bool %t) ", condition)
		write_compiler_point_literal(builder, point)
		strings.write_byte(builder, ' ')
		write_compiler_point_literal(builder, other)
		strings.write_string(builder, ")] (pbt-point-score point))")
		return compiler_point_score(point) if condition else compiler_point_score(other)
	}
	return 0
}

generated_compiler_point :: proc(t: ^pbt.T) -> Compiler_Point_Model {
	return {
		x = pbt.draw(t, pbt.int_range(-8, 8)),
		y = pbt.draw(t, pbt.int_range(-8, 8)),
		weight = pbt.draw(t, pbt.int_range(-8, 8)),
		active = pbt.draw(t, pbt.boolean()),
	}
}

write_compiler_point_literal :: proc(builder: ^strings.Builder, point: Compiler_Point_Model) {
	strings.write_string(builder, "(Pbt-Point :x ")
	fmt.sbprintf(
		builder,
		"%d :y %d :weight %d :active? %t",
		point.x,
		point.y,
		point.weight,
		point.active,
	)
	strings.write_string(builder, ")")
}

compiler_point_score :: proc(point: Compiler_Point_Model) -> int {
	return point.x * 31 + point.y * 17 + point.weight * 13 + (1 if point.active else 0)
}
