// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

COMPILER_PHASE_NAMES := [?]string{"Queued", "Running", "Done", "Failed"}
COMPILER_PHASE_CODES := [?]int{2, 5, 9, 14}

Compiler_Enum_Stats :: struct {
	implicit_selector:  int,
	qualified_selector: int,
	explicit_cast:      int,
	case_form:          int,
	branch:             int,
	struct_field:       int,
	assoc:              int,
	mutation:           int,
	array:              int,
	equality:           int,
}

generated_compiler_enum_expressions_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	stats: Compiler_Enum_Stats
	expected := write_compiler_enum_expression(t, &builder, &stats)
	expression := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("expression=%s expected=%d", expression, expected))

	pbt.cover(t, stats.implicit_selector > 0, 3, "implicit-selector")
	pbt.cover(t, stats.qualified_selector > 0, 3, "qualified-selector")
	pbt.cover(t, stats.explicit_cast > 0, 3, "explicit-cast")
	pbt.cover(t, stats.case_form > 0, 3, "case")
	pbt.cover(t, stats.branch > 0, 3, "branch")
	pbt.cover(t, stats.struct_field > 0, 3, "struct-field")
	pbt.cover(t, stats.assoc > 0, 3, "assoc")
	pbt.cover(t, stats.mutation > 0, 3, "mutation")
	pbt.cover(t, stats.array > 0, 3, "array")
	pbt.cover(t, stats.equality > 0, 3, "equality")

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
			"compiler enum expression mismatch: expected=%d actual=%d expression=%s",
			expected,
			actual,
			expression,
		))
	}
	return pbt.pass()
}

write_compiler_enum_expression :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^Compiler_Enum_Stats,
) -> int {
	kind := pbt.draw(t, pbt.int_range(0, 9))
	phase := pbt.draw(t, pbt.int_range(0, len(COMPILER_PHASE_NAMES) - 1))
	code := COMPILER_PHASE_CODES[phase]

	switch kind {
	case 0:
		stats.implicit_selector += 1
		strings.write_string(builder, "(pbt-phase-score ")
		write_compiler_phase_selector(builder, phase, false)
		strings.write_byte(builder, ')')
		return code
	case 1:
		stats.qualified_selector += 1
		strings.write_string(builder, "(pbt-phase-score ")
		write_compiler_phase_selector(builder, phase, true)
		strings.write_byte(builder, ')')
		return code
	case 2:
		stats.explicit_cast += 1
		fmt.sbprintf(builder, "(int (Pbt-Phase %d))", code)
		return code
	case 3:
		stats.case_form += 1
		fmt.sbprintf(builder, "(case (Pbt-Phase %d) .Queued 20 .Running 50 .Done 90 .Failed 140 -1)", code)
		return code * 10
	case 4:
		stats.branch += 1
		condition := pbt.draw(t, pbt.boolean())
		other := pbt.draw(t, pbt.int_range(0, len(COMPILER_PHASE_NAMES) - 1))
		fmt.sbprintf(builder, "(let [phase: Pbt-Phase (if (identity-bool %t) ", condition)
		write_compiler_phase_selector(builder, phase, false)
		strings.write_byte(builder, ' ')
		write_compiler_phase_selector(builder, other, false)
		strings.write_string(builder, ")] (pbt-phase-score phase))")
		return code if condition else COMPILER_PHASE_CODES[other]
	case 5:
		stats.struct_field += 1
		priority := pbt.draw(t, pbt.int_range(-8, 8))
		strings.write_string(builder, "(pbt-job-score (Pbt-Job {phase: ")
		write_compiler_phase_selector(builder, phase, false)
		fmt.sbprintf(builder, " priority: %d}))", priority)
		return code * 31 + priority
	case 6:
		stats.assoc += 1
		priority := pbt.draw(t, pbt.int_range(-8, 8))
		other := pbt.draw(t, pbt.int_range(0, len(COMPILER_PHASE_NAMES) - 1))
		strings.write_string(builder, "(let [original (Pbt-Job {phase: ")
		write_compiler_phase_selector(builder, phase, false)
		fmt.sbprintf(builder, " priority: %d}) newer (assoc original.phase ", priority)
		write_compiler_phase_selector(builder, other, false)
		strings.write_string(builder, ")] (+ (* (pbt-job-score original) 7) (pbt-job-score newer)))")
		return (code * 31 + priority) * 7 + COMPILER_PHASE_CODES[other] * 31 + priority
	case 7:
		stats.mutation += 1
		priority := pbt.draw(t, pbt.int_range(-8, 8))
		other := pbt.draw(t, pbt.int_range(0, len(COMPILER_PHASE_NAMES) - 1))
		strings.write_string(builder, "(let [job (Pbt-Job {phase: ")
		write_compiler_phase_selector(builder, phase, false)
		fmt.sbprintf(builder, " priority: %d})] (set! job.phase ", priority)
		write_compiler_phase_selector(builder, other, false)
		strings.write_string(builder, ") (pbt-job-score job))")
		return COMPILER_PHASE_CODES[other] * 31 + priority
	case 8:
		stats.array += 1
		second := pbt.draw(t, pbt.int_range(0, len(COMPILER_PHASE_NAMES) - 1))
		third := pbt.draw(t, pbt.int_range(0, len(COMPILER_PHASE_NAMES) - 1))
		index := pbt.draw(t, pbt.int_range(0, 2))
		strings.write_string(builder, "(let [phases ([3]Pbt-Phase [")
		write_compiler_phase_selector(builder, phase, false)
		strings.write_byte(builder, ' ')
		write_compiler_phase_selector(builder, second, false)
		strings.write_byte(builder, ' ')
		write_compiler_phase_selector(builder, third, false)
		fmt.sbprintf(builder, "])] (pbt-phase-score (get phases %d)))", index)
		indices := [3]int{phase, second, third}
		return COMPILER_PHASE_CODES[indices[index]]
	case 9:
		stats.equality += 1
		other := pbt.draw(t, pbt.int_range(0, len(COMPILER_PHASE_NAMES) - 1))
		fmt.sbprintf(
			builder,
			"(if (= (Pbt-Phase %d) (Pbt-Phase %d)) 1 0)",
			code,
			COMPILER_PHASE_CODES[other],
		)
		return 1 if phase == other else 0
	}
	return 0
}

write_compiler_phase_selector :: proc(builder: ^strings.Builder, phase: int, qualified: bool) {
	if qualified {
		strings.write_string(builder, "Pbt-Phase.")
	} else {
		strings.write_byte(builder, '.')
	}
	strings.write_string(builder, COMPILER_PHASE_NAMES[phase])
}
