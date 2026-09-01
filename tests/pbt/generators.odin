package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"

MAX_FORM_DEPTH :: 4

Generated_Form_Kind :: enum {
	Atom,
	List,
	Vector,
	Brace,
	Set,
	Reader_Sugar,
	Discard,
}

Generated_Form :: struct {
	kind:  Generated_Form_Kind,
	text:  string,
	items: []Generated_Form,
}

Render_Style :: enum {
	Compact,
	Noisy,
}

Render_Stats :: struct {
	commas:   int,
	comments: int,
	newlines: int,
}

generate_form :: proc(t: ^pbt.T, depth: int) -> Generated_Form {
	choice_max := 6
	if depth < MAX_FORM_DEPTH {
		choice_max = 12
	}
	choice := pbt.draw(t, pbt.int_range(0, choice_max))
	switch choice {
	case 0:
		return {kind = .Atom, text = "nil"}
	case 1:
		if pbt.draw(t, pbt.boolean()) {
			return {kind = .Atom, text = "true"}
		}
		return {kind = .Atom, text = "false"}
	case 2:
		return {
			kind = .Atom,
			text = strings.clone(
				fmt.tprintf("%d", pbt.draw(t, pbt.int_range(-10_000, 10_000))),
				t.value_allocator,
			),
		}
	case 3:
		return {kind = .Atom, text = pbt.draw(t, pbt.identifier_ascii(1, 16))}
	case 4:
		return {kind = .Atom, text = generated_prefixed_identifier(t, ":")}
	case 5:
		return {kind = .Atom, text = generated_escaped_literal(t, false)}
	case 6:
		return {kind = .Atom, text = generated_escaped_literal(t, true)}
	case 7:
		return generated_container(t, depth, .List)
	case 8:
		return generated_container(t, depth, .Vector)
	case 9:
		return generated_container(t, depth, .Brace)
	case 10:
		return generated_container(t, depth, .Set)
	case 11:
		prefixes := [?]string{"'", "`", "~", "~@"}
		items := make([]Generated_Form, 1, t.value_allocator)
		items[0] = generate_form(t, depth+1)
		return {
			kind = .Reader_Sugar,
			text = prefixes[pbt.draw(t, pbt.int_range(0, len(prefixes)-1))],
			items = items,
		}
	case 12:
		items := make([]Generated_Form, 2, t.value_allocator)
		items[0] = generate_form(t, depth+1)
		items[1] = generate_form(t, depth+1)
		return {kind = .Discard, items = items}
	}
	return {kind = .Atom, text = "nil"}
}

generate_forms :: proc(t: ^pbt.T, min_count, max_count: int) -> []Generated_Form {
	count := pbt.draw(t, pbt.int_range(min_count, max_count))
	forms := make([]Generated_Form, count, t.value_allocator)
	for index in 0 ..< count {
		forms[index] = generate_form(t, 0)
	}
	return forms
}

generated_container :: proc(t: ^pbt.T, depth: int, kind: Generated_Form_Kind) -> Generated_Form {
	item_count := pbt.draw(t, pbt.int_range(0, 4))
	items := make([]Generated_Form, item_count, t.value_allocator)
	for index in 0 ..< item_count {
		items[index] = generate_form(t, depth+1)
	}
	return {kind = kind, items = items}
}

generated_prefixed_identifier :: proc(t: ^pbt.T, prefix: string) -> string {
	identifier := pbt.draw(t, pbt.identifier_ascii(1, 16))
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	strings.write_string(&builder, prefix)
	strings.write_string(&builder, identifier)
	return strings.to_string(builder)
}

generated_escaped_literal :: proc(t: ^pbt.T, regex: bool) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	if regex {
		strings.write_string(&builder, "#\"")
	} else {
		strings.write_byte(&builder, '"')
	}
	part_count := pbt.draw(t, pbt.int_range(0, 12))
	for _ in 0 ..< part_count {
		choice_max := 7
		if regex {
			choice_max = 9
		}
		switch pbt.draw(t, pbt.int_range(0, choice_max)) {
		case 0 ..= 3:
			alphabet := "abcdefghijklmnopqrstuvwxyz0123456789 _-"
			index := pbt.draw(t, pbt.int_range(0, len(alphabet)-1))
			strings.write_byte(&builder, alphabet[index])
		case 4:
			strings.write_string(&builder, "\\\"")
		case 5:
			strings.write_string(&builder, "\\\\")
		case 6:
			strings.write_string(&builder, "\\n")
		case 7:
			strings.write_string(&builder, "\\t")
		case 8:
			strings.write_string(&builder, "\\d")
		case 9:
			strings.write_string(&builder, "\\s")
		}
	}
	strings.write_byte(&builder, '"')
	return strings.to_string(builder)
}

render_forms :: proc(
	t: ^pbt.T,
	forms: []Generated_Form,
	style: Render_Style,
	stats: ^Render_Stats = nil,
) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	for form, index in forms {
		if index > 0 {
			write_render_separator(t, &builder, style, stats)
		}
		render_form(t, &builder, form, style, stats)
	}
	return strings.to_string(builder)
}

render_single_form :: proc(t: ^pbt.T, form: Generated_Form, style: Render_Style) -> string {
	forms := [?]Generated_Form{form}
	return render_forms(t, forms[:], style)
}

render_form :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	form: Generated_Form,
	style: Render_Style,
	stats: ^Render_Stats,
) {
	switch form.kind {
	case .Atom:
		strings.write_string(builder, form.text)
	case .List, .Vector, .Brace, .Set:
		open, close := generated_container_delimiters(form.kind)
		strings.write_string(builder, open)
		if style == .Noisy && (len(form.items) == 0 || pbt.draw(t, pbt.boolean())) {
			write_render_separator(t, builder, style, stats)
		}
		for item, index in form.items {
			if index > 0 {
				write_render_separator(t, builder, style, stats)
			}
			render_form(t, builder, item, style, stats)
		}
		if style == .Noisy && len(form.items) > 0 && pbt.draw(t, pbt.boolean()) {
			write_render_separator(t, builder, style, stats)
		}
		strings.write_string(builder, close)
	case .Reader_Sugar:
		strings.write_string(builder, form.text)
		if style == .Noisy && pbt.draw(t, pbt.boolean()) {
			write_render_separator(t, builder, style, stats)
		}
		render_form(t, builder, form.items[0], style, stats)
	case .Discard:
		strings.write_string(builder, "#_")
		if style == .Noisy && pbt.draw(t, pbt.boolean()) {
			write_render_separator(t, builder, style, stats)
		}
		render_form(t, builder, form.items[0], style, stats)
		write_render_separator(t, builder, style, stats)
		render_form(t, builder, form.items[1], style, stats)
	}
}

generated_container_delimiters :: proc(kind: Generated_Form_Kind) -> (string, string) {
	switch kind {
	case .List:
		return "(", ")"
	case .Vector:
		return "[", "]"
	case .Brace:
		return "{", "}"
	case .Set:
		return "#{", "}"
	case .Atom, .Reader_Sugar, .Discard:
		return "", ""
	}
	return "", ""
}

write_render_separator :: proc(
	t: ^pbt.T,
	builder: ^strings.Builder,
	style: Render_Style,
	stats: ^Render_Stats,
) {
	if style == .Compact {
		strings.write_byte(builder, ' ')
		return
	}
	switch pbt.draw(t, pbt.int_range(0, 5)) {
	case 0:
		strings.write_byte(builder, ' ')
	case 1:
		strings.write_byte(builder, '\n')
		if stats != nil { stats.newlines += 1 }
	case 2:
		strings.write_byte(builder, ',')
		if stats != nil { stats.commas += 1 }
	case 3:
		strings.write_string(builder, " \t ")
	case 4:
		strings.write_string(builder, " ; generated separator\n")
		if stats != nil {
			stats.comments += 1
			stats.newlines += 1
		}
	case 5:
		strings.write_string(builder, ", \n")
		if stats != nil {
			stats.commas += 1
			stats.newlines += 1
		}
	}
}
