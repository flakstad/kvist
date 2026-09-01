package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

Compiler_Map_Model :: struct {
	keys:   [5]int,
	values: [5]int,
	length: int,
}

Compiler_Map_Set_Stats :: struct {
	map_lookup:    int,
	map_contains:  int,
	map_hit:       int,
	map_miss:      int,
	map_mutation:  int,
	empty_map:     int,
	set_contains:  int,
	set_hit:       int,
	set_miss:      int,
	empty_set:     int,
	map_branch:    int,
	set_branch:    int,
}

generated_compiler_map_set_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Map_Set_Stats
	expected := write_compiler_map_set_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.map_lookup > 0, 3, "map-lookup")
	pbt.cover(t, stats.map_contains > 0, 3, "map-contains")
	pbt.cover(t, stats.map_hit > 0, 3, "map-hit")
	pbt.cover(t, stats.map_miss > 0, 3, "map-miss")
	pbt.cover(t, stats.map_mutation > 0, 3, "map-mutation")
	pbt.cover(t, stats.empty_map > 0, 3, "typed-empty-map")
	pbt.cover(t, stats.set_contains > 0, 3, "set-contains")
	pbt.cover(t, stats.set_hit > 0, 3, "set-hit")
	pbt.cover(t, stats.set_miss > 0, 3, "set-miss")
	pbt.cover(t, stats.empty_set > 0, 3, "typed-empty-set")
	pbt.cover(t, stats.map_branch > 0, 3, "map-branch")
	pbt.cover(t, stats.set_branch > 0, 3, "set-branch")

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
			"compiler map/set expression mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_map_set_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Map_Set_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 8))
	if kind == 3 {
		stats.empty_map += 1
		strings.write_string(builder, "(let [lookup: map[int]int {} :defer] (count lookup))")
		return 0
	}
	if kind == 6 {
		stats.empty_set += 1
		strings.write_string(builder, "(let [members: (map int (struct {})) #{} :defer] (count members))")
		return 0
	}

	model := generated_compiler_map_model(t)
	switch kind {
	case 0:
		stats.map_lookup += 1
		stats.map_contains += 1
		stats.map_hit += 1
		stats.map_miss += 1
		index := pbt.draw(t, pbt.int_range(0, model.length - 1))
		missing := model.keys[model.length - 1] + 7
		strings.write_string(builder, "(let [lookup ")
		write_compiler_map_literal(builder, model)
		fmt.sbprintf(
			builder,
			" :defer] (+ (* (count lookup) 31) (* (get lookup %d) 17) (if (contains? lookup %d) 1 0) (if (contains? lookup %d) 2 0)))",
			model.keys[index],
			model.keys[index],
			missing,
		)
		return model.length * 31 + model.values[index] * 17 + 1
	case 1:
		stats.map_contains += 1
		hit := pbt.draw(t, pbt.boolean())
		probe := model.keys[model.length - 1] + 7
		if hit {
			stats.map_hit += 1
			probe = model.keys[pbt.draw(t, pbt.int_range(0, model.length - 1))]
		} else {
			stats.map_miss += 1
		}
		strings.write_string(builder, "(let [lookup ")
		write_compiler_map_literal(builder, model)
		fmt.sbprintf(builder, " :defer] (if (contains? lookup %d) 1 0))", probe)
		return 1 if hit else 0
	case 2:
		stats.map_mutation += 1
		index := pbt.draw(t, pbt.int_range(0, model.length - 1))
		replacement := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(let [lookup ")
		write_compiler_map_literal(builder, model)
		fmt.sbprintf(
			builder,
			" :defer before (get lookup %d)] (set! (get lookup %d) %d) (+ (* before 31) (* (get lookup %d) 17) (count lookup)))",
			model.keys[index],
			model.keys[index],
			replacement,
			model.keys[index],
		)
		return model.values[index] * 31 + replacement * 17 + model.length
	case 4:
		stats.set_contains += 1
		stats.set_hit += 1
		index := pbt.draw(t, pbt.int_range(0, model.length - 1))
		strings.write_string(builder, "(let [members ")
		write_compiler_set_literal(builder, model)
		fmt.sbprintf(
			builder,
			" :defer] (+ (* (count members) 31) (if (contains? members %d) 1 0)))",
			model.keys[index],
		)
		return model.length * 31 + 1
	case 5:
		stats.set_contains += 1
		stats.set_miss += 1
		probe := model.keys[model.length - 1] + 7
		strings.write_string(builder, "(let [members ")
		write_compiler_set_literal(builder, model)
		fmt.sbprintf(builder, " :defer] (if (contains? members %d) 1 0))", probe)
		return 0
	case 7:
		stats.map_branch += 1
		condition := pbt.draw(t, pbt.boolean())
		other := generated_compiler_map_model(t)
		selected := model if condition else other
		index := pbt.draw(t, pbt.int_range(0, selected.length - 1))
		fmt.sbprintf(builder, "(let [lookup: map[int]int (if (identity-bool %t) ", condition)
		write_compiler_map_literal(builder, model)
		strings.write_byte(builder, ' ')
		write_compiler_map_literal(builder, other)
		fmt.sbprintf(builder, ") :defer] (+ (* (count lookup) 31) (get lookup %d)))", selected.keys[index])
		return selected.length * 31 + selected.values[index]
	case 8:
		stats.set_branch += 1
		condition := pbt.draw(t, pbt.boolean())
		other := generated_compiler_map_model(t)
		selected := model if condition else other
		index := pbt.draw(t, pbt.int_range(0, selected.length - 1))
		strings.write_string(builder, "(let [members: (map int (struct {})) (if (identity-bool ")
		fmt.sbprintf(builder, "%t) ", condition)
		write_compiler_set_literal(builder, model)
		strings.write_byte(builder, ' ')
		write_compiler_set_literal(builder, other)
		fmt.sbprintf(
			builder,
			") :defer] (+ (* (count members) 31) (if (contains? members %d) 1 0)))",
			selected.keys[index],
		)
		return selected.length * 31 + 1
	}
	return 0
}

generated_compiler_map_model :: proc(t: ^pbt.T) -> Compiler_Map_Model {
	model: Compiler_Map_Model
	model.length = pbt.draw(t, pbt.int_range(1, 5))
	first_key := pbt.draw(t, pbt.int_range(-8, 4))
	for index in 0 ..< model.length {
		model.keys[index] = first_key + index
		model.values[index] = pbt.draw(t, pbt.int_range(-8, 8))
	}
	return model
}

write_compiler_map_literal :: proc(builder: ^strings.Builder, model: Compiler_Map_Model) {
	strings.write_byte(builder, '{')
	for index in 0 ..< model.length {
		if index > 0 {
			strings.write_byte(builder, ' ')
		}
		fmt.sbprintf(builder, "%d %d", model.keys[index], model.values[index])
	}
	strings.write_byte(builder, '}')
}

write_compiler_set_literal :: proc(builder: ^strings.Builder, model: Compiler_Map_Model) {
	strings.write_string(builder, "#{")
	for index in 0 ..< model.length {
		if index > 0 {
			strings.write_byte(builder, ' ')
		}
		fmt.sbprintf(builder, "%d", model.keys[index])
	}
	strings.write_byte(builder, '}')
}
