// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import kvist "../../src/odin/kvist"

Reader_Corruption :: enum {
	Mismatched_Delimiter,
	Extra_Delimiter,
	Unterminated_String,
	Unterminated_Regex,
}

generated_reader_forms_have_valid_tokens_and_spans :: proc(t: ^pbt.T) -> pbt.Result {
	generated := generate_forms(t, 1, 5)
	source := render_forms(t, generated, .Noisy)
	pbt.note(t, fmt.tprintf("source=%q", source))

	tokens, token_error, token_ok := kvist.tokenize(source)
	defer delete(tokens)
	if !token_ok {
		return pbt.fail(fmt.tprintf("generated valid source did not tokenize: %s", token_error.message))
	}
	if message := validate_token_spans(tokens[:], source); message != "" {
		return pbt.fail(message)
	}

	forms, read_error, read_ok := kvist.read_top_forms(source)
	if !read_ok {
		return pbt.fail(fmt.tprintf("generated valid source did not parse: %s", read_error.message))
	}
	defer kvist.delete_borrowed_cst_top_form_slice(&forms)
	if len(forms) != len(generated) {
		return pbt.fail(fmt.tprintf("expected %d top forms, got %d", len(generated), len(forms)))
	}
	for form, index in forms {
		if form.source != source[form.form.span.start:form.form.span.end] {
			return pbt.fail(fmt.tprintf("top form %d source does not match its span", index))
		}
		if message := validate_form_spans(form.form, 0, len(source), source); message != "" {
			return pbt.fail(fmt.tprintf("top form %d: %s", index, message))
		}
	}
	return pbt.pass()
}

reader_layout_does_not_change_cst :: proc(t: ^pbt.T) -> pbt.Result {
	generated := generate_forms(t, 1, 5)
	compact := render_forms(t, generated, .Compact)
	stats: Render_Stats
	noisy := render_forms(t, generated, .Noisy, &stats)
	pbt.note(t, fmt.tprintf("compact=%q noisy=%q", compact, noisy))
	pbt.cover(t, stats.comments > 0, 10, "comments")
	pbt.cover(t, stats.commas > 0, 10, "commas")
	pbt.cover(t, stats.newlines > 0, 15, "newlines")

	compact_forms, compact_error, compact_ok := kvist.read_top_forms(compact)
	if !compact_ok {
		return pbt.fail(fmt.tprintf("compact generated source did not parse: %s", compact_error.message))
	}
	defer kvist.delete_borrowed_cst_top_form_slice(&compact_forms)
	noisy_forms, noisy_error, noisy_ok := kvist.read_top_forms(noisy)
	if !noisy_ok {
		return pbt.fail(fmt.tprintf("layout-perturbed source did not parse: %s", noisy_error.message))
	}
	defer kvist.delete_borrowed_cst_top_form_slice(&noisy_forms)

	if len(compact_forms) != len(noisy_forms) {
		return pbt.fail(fmt.tprintf(
			"layout changed top-form count from %d to %d",
			len(compact_forms),
			len(noisy_forms),
		))
	}
	for index in 0 ..< len(compact_forms) {
		if !forms_equal_ignoring_spans(compact_forms[index].form, noisy_forms[index].form) {
			return pbt.fail(fmt.tprintf("layout changed CST shape for top form %d", index))
		}
	}
	return pbt.pass()
}

reader_sugar_matches_explicit_forms :: proc(t: ^pbt.T) -> pbt.Result {
	prefixes := [?]string{"'", "`", "~", "~@"}
	heads := [?]string{"quote", "quasiquote", "unquote", "splice"}
	choice := pbt.draw(t, pbt.int_range(0, len(prefixes)-1))
	identifier := pbt.draw(t, pbt.identifier_ascii(1, 16))

	sugar := fmt.tprintf("%s%s", prefixes[choice], identifier)
	explicit := fmt.tprintf("(%s %s)", heads[choice], identifier)
	pbt.note(t, fmt.tprintf("sugar=%q explicit=%q", sugar, explicit))

	sugar_forms, sugar_error, sugar_ok := kvist.read_top_forms(sugar)
	if !sugar_ok {
		return pbt.fail(fmt.tprintf("reader sugar failed: %s", sugar_error.message))
	}
	defer kvist.delete_borrowed_cst_top_form_slice(&sugar_forms)
	explicit_forms, explicit_error, explicit_ok := kvist.read_top_forms(explicit)
	if !explicit_ok {
		return pbt.fail(fmt.tprintf("explicit reader form failed: %s", explicit_error.message))
	}
	defer kvist.delete_borrowed_cst_top_form_slice(&explicit_forms)

	if len(sugar_forms) != 1 || len(explicit_forms) != 1 {
		return pbt.fail("reader sugar comparison did not produce one top form per input")
	}
	if !forms_equal_ignoring_spans(sugar_forms[0].form, explicit_forms[0].form) {
		return pbt.fail("reader sugar and explicit form produced different CST shapes")
	}
	return pbt.pass()
}

missing_generated_closing_delimiter_is_rejected :: proc(t: ^pbt.T) -> pbt.Result {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	strings.write_byte(&builder, '(')
	generated := generate_form(t, 0)
	render_form(t, &builder, generated, .Compact, nil)
	source := strings.to_string(builder)
	pbt.note(t, fmt.tprintf("source=%q", source))

	forms, read_error, read_ok := kvist.read_top_forms(source)
	if read_ok {
		kvist.delete_borrowed_cst_top_form_slice(&forms)
		return pbt.fail("reader accepted a generated list without its closing delimiter")
	}
	if !strings.contains(read_error.message, "missing closing delimiter") {
		return pbt.fail(fmt.tprintf("unexpected error for missing delimiter: %s", read_error.message))
	}
	if read_error.span.start < 0 ||
	   read_error.span.start > read_error.span.end ||
	   read_error.span.end > len(source) {
		return pbt.fail(fmt.tprintf(
			"error span [%d,%d) is outside source length %d",
			read_error.span.start,
			read_error.span.end,
			len(source),
		))
	}
	return pbt.pass()
}

generated_reader_corruption_is_rejected :: proc(t: ^pbt.T) -> pbt.Result {
	corruption := Reader_Corruption(pbt.draw(t, pbt.int_range(0, 3)))
	pbt.cover(t, corruption == .Mismatched_Delimiter, 15, "mismatched-delimiter")
	pbt.cover(t, corruption == .Extra_Delimiter, 15, "extra-delimiter")
	pbt.cover(t, corruption == .Unterminated_String, 15, "unterminated-string")
	pbt.cover(t, corruption == .Unterminated_Regex, 15, "unterminated-regex")

	source, expected_message := generated_corrupt_source(t, corruption)
	pbt.note(t, fmt.tprintf("corruption=%v source=%q", corruption, source))
	forms, read_error, read_ok := kvist.read_top_forms(source)
	if read_ok {
		kvist.delete_borrowed_cst_top_form_slice(&forms)
		return pbt.fail(fmt.tprintf("reader accepted %v corruption", corruption))
	}
	if !strings.contains(read_error.message, expected_message) {
		return pbt.fail(fmt.tprintf(
			"%v corruption produced %q, expected message containing %q",
			corruption,
			read_error.message,
			expected_message,
		))
	}
	if message := validate_error_span(read_error.span, source); message != "" {
		return pbt.fail(message)
	}
	return pbt.pass()
}

generated_corrupt_source :: proc(t: ^pbt.T, corruption: Reader_Corruption) -> (string, string) {
	switch corruption {
	case .Mismatched_Delimiter:
		container_kinds := [?]Generated_Form_Kind{.List, .Vector, .Brace, .Set}
		kind := container_kinds[pbt.draw(t, pbt.int_range(0, len(container_kinds)-1))]
		valid := render_single_form(t, generated_container(t, 0, kind), .Compact)
		_, correct_close := generated_container_delimiters(kind)
		wrong_closes: [2]string
		switch correct_close {
		case ")":
			wrong_closes = {"]", "}"}
		case "]":
			wrong_closes = {")", "}"}
		case "}":
			wrong_closes = {")", "]"}
		}
		wrong_close := wrong_closes[pbt.draw(t, pbt.int_range(0, len(wrong_closes)-1))]
		builder: strings.Builder
		strings.builder_init(&builder, t.value_allocator)
		strings.write_string(&builder, valid[:len(valid)-len(correct_close)])
		strings.write_string(&builder, wrong_close)
		return strings.to_string(builder), "unexpected closing delimiter"
	case .Extra_Delimiter:
		valid := render_forms(t, generate_forms(t, 1, 4), .Compact)
		extra_closes := [?]string{")", "]", "}"}
		builder: strings.Builder
		strings.builder_init(&builder, t.value_allocator)
		strings.write_string(&builder, valid)
		strings.write_string(&builder, extra_closes[pbt.draw(t, pbt.int_range(0, len(extra_closes)-1))])
		return strings.to_string(builder), "unexpected closing delimiter"
	case .Unterminated_String:
		valid := generated_escaped_literal(t, false)
		return valid[:len(valid)-1], "unterminated string literal"
	case .Unterminated_Regex:
		valid := generated_escaped_literal(t, true)
		return valid[:len(valid)-1], "unterminated regex literal"
	}
	return "", ""
}

validate_error_span :: proc(span: kvist.Span, source: string) -> string {
	if span.start < 0 || span.start > span.end || span.end > len(source) {
		return fmt.tprintf(
			"error span [%d,%d) is outside source length %d",
			span.start,
			span.end,
			len(source),
		)
	}
	return ""
}

validate_token_spans :: proc(tokens: []kvist.Token, source: string) -> string {
	if len(tokens) == 0 {
		return "tokenizer returned no EOF token"
	}
	previous_end := 0
	for token, index in tokens {
		if token.span.start < previous_end ||
		   token.span.start < 0 ||
		   token.span.start > token.span.end ||
		   token.span.end > len(source) {
			return fmt.tprintf(
				"token %d has invalid or non-monotone span [%d,%d) after %d",
				index,
				token.span.start,
				token.span.end,
				previous_end,
			)
		}
		if token.text != source[token.span.start:token.span.end] {
			return fmt.tprintf("token %d text does not match its source span", index)
		}
		previous_end = token.span.end
	}
	last := tokens[len(tokens)-1]
	if last.kind != .EOF || last.span.start != len(source) || last.span.end != len(source) {
		return "token stream does not end with an EOF token at the end of the source"
	}
	return ""
}

validate_form_spans :: proc(form: kvist.CST_Form, parent_start, parent_end: int, source: string) -> string {
	if form.span.start < parent_start ||
	   form.span.start > form.span.end ||
	   form.span.end > parent_end ||
	   form.span.end > len(source) {
		return fmt.tprintf(
			"form span [%d,%d) is outside parent [%d,%d)",
			form.span.start,
			form.span.end,
			parent_start,
			parent_end,
		)
	}
	for child in form.items {
		if message := validate_form_spans(child, form.span.start, form.span.end, source); message != "" {
			return message
		}
	}
	return ""
}

forms_equal_ignoring_spans :: proc(left, right: kvist.CST_Form) -> bool {
	if left.kind != right.kind || left.text != right.text || len(left.items) != len(right.items) {
		return false
	}
	for index in 0 ..< len(left.items) {
		if !forms_equal_ignoring_spans(left.items[index], right.items[index]) {
			return false
		}
	}
	return true
}
