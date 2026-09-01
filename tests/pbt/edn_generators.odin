package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"

MAX_EDN_DEPTH :: 4

EDN_Generation_Stats :: struct {
	floats:          int,
	integral_floats: int,
	strings:         int,
	collections:     int,
	maps:            int,
	tagged:          int,
	commas:          int,
	comments:        int,
}

generated_edn_source :: proc(t: ^pbt.T, stats: ^EDN_Generation_Stats) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	write_generated_edn(t, &builder, 0, stats)
	return strings.to_string(builder)
}

write_generated_edn :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	depth: int,
	stats: ^EDN_Generation_Stats,
) {
	choice_max := 6
	if depth < MAX_EDN_DEPTH {
		choice_max = 11
	}
	switch pbt.draw(t, pbt.int_range(0, choice_max)) {
	case 0:
		strings.write_string(builder, "nil")
	case 1:
		if pbt.draw(t, pbt.boolean()) {
			strings.write_string(builder, "true")
		} else {
			strings.write_string(builder, "false")
		}
	case 2:
		fmt.sbprintf(builder, "%d", pbt.draw(t, pbt.int_range(-100_000, 100_000)))
	case 3:
		stats.floats += 1
		whole := pbt.draw(t, pbt.int_range(-10_000, 10_000))
		integral := pbt.draw(t, pbt.boolean())
		fraction := 0
		if integral {
			stats.integral_floats += 1
		} else {
			fraction = pbt.draw(t, pbt.int_range(1, 999))
		}
		fmt.sbprintf(builder, "%d.%03d", whole, fraction)
	case 4:
		stats.strings += 1
		strings.write_string(builder, generated_escaped_literal(t, false))
	case 5:
		strings.write_string(builder, pbt.draw(t, pbt.identifier_ascii(1, 16)))
	case 6:
		strings.write_string(builder, generated_prefixed_identifier(t, ":"))
	case 7:
		stats.collections += 1
		write_generated_edn_sequence(t, builder, depth, "(", ")", stats)
	case 8:
		stats.collections += 1
		write_generated_edn_sequence(t, builder, depth, "[", "]", stats)
	case 9:
		stats.collections += 1
		write_generated_edn_sequence(t, builder, depth, "#{", "}", stats)
	case 10:
		stats.collections += 1
		stats.maps += 1
		write_generated_edn_map(t, builder, depth, stats)
	case 11:
		stats.tagged += 1
		strings.write_byte(builder, '#')
		strings.write_string(builder, pbt.draw(t, pbt.identifier_ascii(1, 12)))
		write_generated_edn_separator(t, builder, stats)
		write_generated_edn(t, builder, depth+1, stats)
	}
}

write_generated_edn_sequence :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	depth: int,
	open, close: string,
	stats: ^EDN_Generation_Stats,
) {
	strings.write_string(builder, open)
	item_count := pbt.draw(t, pbt.int_range(0, 4))
	if item_count == 0 && pbt.draw(t, pbt.boolean()) {
		write_generated_edn_separator(t, builder, stats)
	}
	for index in 0 ..< item_count {
		if index > 0 {
			write_generated_edn_separator(t, builder, stats)
		}
		write_generated_edn(t, builder, depth+1, stats)
	}
	if item_count > 0 && pbt.draw(t, pbt.boolean()) {
		write_generated_edn_separator(t, builder, stats)
	}
	strings.write_string(builder, close)
}

write_generated_edn_map :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	depth: int,
	stats: ^EDN_Generation_Stats,
) {
	strings.write_byte(builder, '{')
	entry_count := pbt.draw(t, pbt.int_range(0, 4))
	if entry_count == 0 && pbt.draw(t, pbt.boolean()) {
		write_generated_edn_separator(t, builder, stats)
	}
	for index in 0 ..< entry_count {
		if index > 0 {
			write_generated_edn_separator(t, builder, stats)
		}
		fmt.sbprintf(builder, ":key%d", index)
		write_generated_edn_separator(t, builder, stats)
		write_generated_edn(t, builder, depth+1, stats)
	}
	if entry_count > 0 && pbt.draw(t, pbt.boolean()) {
		write_generated_edn_separator(t, builder, stats)
	}
	strings.write_byte(builder, '}')
}

write_generated_edn_separator :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	stats: ^EDN_Generation_Stats,
) {
	switch pbt.draw(t, pbt.int_range(0, 5)) {
	case 0:
		strings.write_byte(builder, ' ')
	case 1:
		strings.write_byte(builder, '\n')
	case 2:
		strings.write_byte(builder, ',')
		stats.commas += 1
	case 3:
		strings.write_string(builder, " \t ")
	case 4:
		strings.write_string(builder, " ; generated EDN separator\n")
		stats.comments += 1
	case 5:
		strings.write_string(builder, ", \n")
		stats.commas += 1
	}
}
