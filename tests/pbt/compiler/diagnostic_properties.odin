package main

import "core:fmt"
import "core:strings"

import pbt "pbt:pbt"
import kvist "../../../src/odin/kvist"

Compiler_Diagnostic_Kind :: enum {
	Not_Arity,
	If_Arity,
	Not_Equal_Arity,
	Case_Missing_Default,
	If_Branch_Mismatch,
	Case_Branch_Mismatch,
	Set_Non_Place,
	Mut_Non_Place,
	Removed_In,
	Statement_Expression,
}

COMPILER_DIAGNOSTIC_NAMES := [?]string{
	"not-arity",
	"if-arity",
	"not-equal-arity",
	"case-missing-default",
	"if-branch-mismatch",
	"case-branch-mismatch",
	"set-non-place",
	"mut-non-place",
	"removed-in",
	"statement-expression",
}

generated_invalid_compiler_expressions_have_bounded_diagnostics :: proc(t: ^pbt.T) -> pbt.Result {
	kind := Compiler_Diagnostic_Kind(pbt.draw(t, pbt.int_range(0, len(COMPILER_DIAGNOSTIC_NAMES) - 1)))
	expression, expected_message := generated_invalid_compiler_expression(t, kind)
	pbt.note(t, fmt.tprintf("kind=%s expression=%s", COMPILER_DIAGNOSTIC_NAMES[kind], expression))
	for name, index in COMPILER_DIAGNOSTIC_NAMES {
		pbt.cover(t, int(kind) == index, 3, name)
	}

	output, compile_error, ok := kvist.compile_eval_source("(package main)", expression)
	if ok {
		delete(output)
		return pbt.fail(fmt.tprintf("compiler accepted invalid %s expression: %s", COMPILER_DIAGNOSTIC_NAMES[kind], expression))
	}
	defer delete(compile_error.message)
	if !strings.contains(compile_error.message, expected_message) {
		return pbt.fail(fmt.tprintf(
			"unexpected %s diagnostic: expected message containing %q, actual=%q",
			COMPILER_DIAGNOSTIC_NAMES[kind],
			expected_message,
			compile_error.message,
		))
	}
	if compile_error.span.source != .Eval {
		return pbt.fail(fmt.tprintf(
			"%s diagnostic has source %v instead of Eval",
			COMPILER_DIAGNOSTIC_NAMES[kind],
			compile_error.span.source,
		))
	}
	if compile_error.span.start < 0 ||
	   compile_error.span.start > compile_error.span.end ||
	   compile_error.span.end > len(expression) {
		return pbt.fail(fmt.tprintf(
			"%s diagnostic span [%d,%d) is outside expression length %d",
			COMPILER_DIAGNOSTIC_NAMES[kind],
			compile_error.span.start,
			compile_error.span.end,
			len(expression),
		))
	}
	return pbt.pass()
}

generated_invalid_compiler_expression :: proc(
	t: ^pbt.T,
	kind: Compiler_Diagnostic_Kind,
) -> (expression, expected_message: string) {
	switch kind {
	case .Not_Arity:
		arity := pbt.draw(t, pbt.int_range(0, 3))
		if arity == 1 {
			arity = 2
		}
		return generated_diagnostic_call(t, "not", arity), "not expects one argument"
	case .If_Arity:
		arity := pbt.draw(t, pbt.int_range(0, 5))
		if arity == 3 {
			arity = 4
		}
		return generated_diagnostic_call(t, "if", arity), "expects test, then"
	case .Not_Equal_Arity:
		arity := pbt.draw(t, pbt.int_range(0, 4))
		if arity == 2 {
			arity = 3
		}
		return generated_diagnostic_call(t, "!=", arity), "!= expects"
	case .Case_Missing_Default:
		value := pbt.draw(t, pbt.int_range(-8, 8))
		match := pbt.draw(t, pbt.int_range(-8, 8))
		return fmt.tprintf("(case %d %d %d)", value, match, value), "case expects subject, clause/body pairs, and default"
	case .If_Branch_Mismatch:
		condition := pbt.draw(t, pbt.boolean())
		return fmt.tprintf("(let [result: string (if %t \"text\" false)] result)", condition), "if expression branches have different obvious types: string and bool"
	case .Case_Branch_Mismatch:
		value := pbt.draw(t, pbt.int_range(-8, 8))
		return fmt.tprintf("(let [result: string (case %d %d \"text\" false)] result)", value, value), "if expression branches have different obvious types: string and bool"
	case .Set_Non_Place:
		left := pbt.draw(t, pbt.int_range(-8, 8))
		right := pbt.draw(t, pbt.int_range(-8, 8))
		return fmt.tprintf("(do (set! (+ %d %d) 0) 0)", left, right), "set! expects an assignable place"
	case .Mut_Non_Place:
		left := pbt.draw(t, pbt.int_range(-8, 8))
		right := pbt.draw(t, pbt.int_range(-8, 8))
		return fmt.tprintf("(do (mut! (+ %d %d) += 1) 0)", left, right), "mut! expects an assignable place"
	case .Removed_In:
		value := pbt.draw(t, pbt.int_range(-8, 8))
		return fmt.tprintf("(in %d [%d])", value, value), "`in` has been removed; use `contains?`"
	case .Statement_Expression:
		value := pbt.draw(t, pbt.int_range(-8, 8))
		return fmt.tprintf("(+ 1 (while false %d))", value), "while is a statement and cannot be used as an expression"
	}
	return "", ""
}

generated_diagnostic_call :: proc(t: ^pbt.T, head: string, arity: int) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, t.value_allocator)
	defer strings.builder_destroy(&builder)
	strings.write_byte(&builder, '(')
	strings.write_string(&builder, head)
	for _ in 0 ..< arity {
		fmt.sbprintf(&builder, " %d", pbt.draw(t, pbt.int_range(-8, 8)))
	}
	strings.write_byte(&builder, ')')
	return strings.to_string(builder)
}
