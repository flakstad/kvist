package main

import "core:fmt"
import "core:os"

import pbt "pbt:pbt"

edn_roundtrip_is_canonical :: proc(t: ^pbt.T) -> pbt.Result {
	stats: EDN_Generation_Stats
	source := generated_edn_source(t, &stats)
	pbt.note(t, fmt.tprintf("source=%q", source))
	pbt.cover(t, stats.floats > 0, 5, "floats")
	pbt.cover(t, stats.integral_floats > 0, 3, "integral-floats")
	pbt.cover(t, stats.strings > 0, 5, "strings")
	pbt.cover(t, stats.collections > 0, 25, "collections")
	pbt.cover(t, stats.maps > 0, 5, "maps")
	pbt.cover(t, stats.tagged > 0, 5, "tagged")
	pbt.cover(t, stats.commas > 0, 5, "commas")
	pbt.cover(t, stats.comments > 0, 3, "comments")

	first, first_ok := run_edn_target(t, source)
	if !first_ok {
		return edn_process_failure(first, "generated EDN")
	}
	if first.stdout == "" {
		return pbt.fail("EDN target returned empty canonical output")
	}

	second, second_ok := run_edn_target(t, first.stdout)
	if !second_ok {
		return edn_process_failure(second, "canonical EDN")
	}
	if second.stdout != first.stdout {
		return pbt.fail(fmt.tprintf(
			"canonical EDN changed on a second process roundtrip: first=%q second=%q",
			first.stdout,
			second.stdout,
		))
	}
	return pbt.pass()
}

run_edn_target :: proc(t: ^pbt.T, input: string) -> (pbt.Process_Result, bool) {
	target := os.get_env("KVIST_PBT_EDN_TARGET", t.value_allocator)
	if target == "" {
		return {error = "KVIST_PBT_EDN_TARGET is not set"}, false
	}
	command := [?]string{target}
	result := pbt.process_run_with_options(t, command[:], {
		stdin = input,
		timeout_ms = 1_000,
		max_output_bytes = 1_048_576,
	})
	return result, result.success
}

edn_process_failure :: proc(result: pbt.Process_Result, phase: string) -> pbt.Result {
	if result.stderr != "" {
		return pbt.fail(fmt.tprintf("%s target stderr: %s", phase, result.stderr))
	}
	if result.error != "" {
		return pbt.fail(fmt.tprintf("%s target error: %s", phase, result.error))
	}
	return pbt.fail(fmt.tprintf("%s target exited with %d", phase, result.exit_code))
}
