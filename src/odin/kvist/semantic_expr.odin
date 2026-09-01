// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:strconv"
import "core:strings"
import repl_plan "../kvist_repl_plan"

// Semantic_Expression_IR is the typed expression boundary shared by the
// resident REPL analyzer and its execution-plan encoder. It deliberately
// models only expressions whose Kvist semantics the resident worker can
// reproduce exactly; unsupported forms remain in the native compiler.
Semantic_Value_Kind :: enum u8 {
    Invalid,
    Bool,
    Int,
    F64,
    String,
    Data,
}

Semantic_Expr_Kind :: enum u8 {
    Invalid,
    Bool_Literal,
    Int_Literal,
    F64_Literal,
    String_Literal,
    Recent_Result,
    Local,
    Let,
    Resident_Call,
    Program_Call,
    Sequence,
    Discard,
    Set_Local,
    While,
    Return,
    Break,
    Continue,
    If,
    Not,
    And,
    Or,
    Add,
    Subtract,
    Multiply,
    Divide,
    Modulo,
    Equal,
    Not_Equal,
    Less,
    Less_Equal,
    Greater,
    Greater_Equal,
}

Semantic_Value :: struct {
    kind:           Semantic_Value_Kind,
    constant:       bool,
    managed_handle: bool,
    int_value:      int,
    float_value:    f64,
    bool_value:     bool,
}

Semantic_Expr :: struct {
    kind:             Semantic_Expr_Kind,
    value:            Semantic_Value,
    span:             Span,
    operand:          int,
    children_start:   int,
    children_count:   int,
    bindings_start:   int,
    bindings_count:   int,
    body:             int,
    resolved_name:    string,
    scalar_signature: string,
    string_value:     string,
}

Semantic_Binding :: struct {
    slot:       int,
    value_expr: int,
    value_kind: Semantic_Value_Kind,
    managed_cleanup: bool,
    span:       Span,
}

Semantic_Expression_IR :: struct {
    expressions:   [dynamic]Semantic_Expr,
    child_indices: [dynamic]int,
    bindings:      [dynamic]Semantic_Binding,
    result_expr:   int,
}

semantic_expression_ir_delete :: proc(ir: ^Semantic_Expression_IR) {
    if ir == nil {
        return
    }
    for expression in ir.expressions {
        if expression.kind == .Resident_Call ||
           expression.kind == .Program_Call {
            delete(expression.resolved_name)
            delete(expression.scalar_signature)
        } else if expression.kind == .String_Literal {
            delete(expression.string_value)
        }
    }
    delete(ir.expressions)
    delete(ir.child_indices)
    delete(ir.bindings)
    ir^ = {}
}

Repl_Semantic_Local :: struct {
    name:    string,
    slot:    int,
    value:   Semantic_Value,
    mutable: bool,
}

Repl_Semantic_Analyzer :: struct {
    ir:                  Semantic_Expression_IR,
    emitter:             ^Emitter,
    recent_result_types: []string,
    stale_proc_names:    []string,
    scalar_invokes:      []Repl_Scalar_Invoke_Metadata,
    program_proc_names:  []string,
    locals:              [dynamic]Repl_Semantic_Local,
    local_kinds:         [dynamic]Semantic_Value_Kind,
    next_local:          int,
    loop_depth:          int,
    procedure_result_kind: Semantic_Value_Kind,
}

semantic_value_kind_for_type :: proc(type_text: string) -> Semantic_Value_Kind {
    switch strings.trim_space(type_text) {
    case "bool": return .Bool
    case "int":  return .Int
    case "f64":  return .F64
    case "string": return .String
    case "Data": return .Data
    }
    return .Invalid
}

semantic_type_for_value_kind :: proc(kind: Semantic_Value_Kind) -> string {
    switch kind {
    case .Bool: return "bool"
    case .Int:  return "int"
    case .F64:  return "f64"
    case .String: return "string"
    case .Data: return "Data"
    case .Invalid:
    }
    return ""
}

semantic_value_kind_to_plan_kind :: proc(
    kind: Semantic_Value_Kind,
) -> repl_plan.Value_Kind {
    switch kind {
    case .Bool: return .Bool
    case .Int:  return .Int
    case .F64:  return .F64
    case .String: return .String
    case .Data: return .Data
    case .Invalid:
    }
    return .Invalid
}

semantic_append_expr :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    expression: Semantic_Expr,
    children: []int = nil,
) -> int {
    stored := expression
    stored.children_start = len(analyzer.ir.child_indices)
    stored.children_count = len(children)
    append(&analyzer.ir.child_indices, ..children)
    index := len(analyzer.ir.expressions)
    append(&analyzer.ir.expressions, stored)
    return index
}

semantic_form_value_kind :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    form: CST_Form,
) -> Semantic_Value_Kind {
    type_text, typed := obvious_form_type(analyzer.emitter, form)
    if !typed {
        return .Invalid
    }
    return semantic_value_kind_for_type(type_text)
}

semantic_resolve_operator :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    source_operator: string,
) -> (string, bool) {
    canonical, matched_builtin, _, resolved :=
        resolve_kvist_head(analyzer.emitter, source_operator)
    if !resolved {
        return "", false
    }
    if !matched_builtin && repl_plan_operator_supported(canonical) {
        mapped := map_name(canonical)
        defer delete(mapped)
        ensure_emitter_indexes(analyzer.emitter)
        if _, declared := analyzer.emitter.decl_indices[mapped]; declared {
            return "", false
        }
    }
    return canonical, true
}

semantic_literal_expr :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    form: CST_Form,
    expected_kind: Semantic_Value_Kind,
) -> (int, bool) {
    if form.kind == .String {
        value, allocated, unquoted := strconv.unquote_string(form.text)
        if !unquoted {
            return 0, false
        }
        owned_value := strings.clone(value)
        if allocated {
            delete(value)
        }
        index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = .String_Literal,
            value = {kind = .String},
            span = form.span,
            string_value = owned_value,
        })
        return index, true
    }
    if form.kind == .Bool {
        value := form.text == "true"
        index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = .Bool_Literal,
            value = {
                kind = .Bool,
                constant = true,
                bool_value = value,
            },
            span = form.span,
        })
        return index, true
    }
    if form.kind != .Number {
        return 0, false
    }
    literal_kind := semantic_value_kind_for_type(
        number_literal_type(form.text),
    )
    if expected_kind == .F64 && literal_kind == .Int {
        // Keep arbitrary-precision constants on the native checker path.
        // Resident execution stores a machine int before contextual f64
        // conversion and must not weaken Odin's range diagnostics.
        if _, parsed_int := repl_plan_parse_int(form.text); !parsed_int {
            return 0, false
        }
        value, parsed := strconv.parse_f64(form.text)
        if !parsed {
            return 0, false
        }
        index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = .F64_Literal,
            value = {
                kind = .F64,
                constant = true,
                float_value = value,
            },
            span = form.span,
        })
        return index, true
    }
    if strings.contains(form.text, ".") ||
       strings.contains(form.text, "e") ||
       strings.contains(form.text, "E") {
        // Generated Odin currently diagnoses positive exponent-only literals
        // such as `1e3` in int storage. Preserve that behavior.
        if !strings.contains(form.text, ".") &&
           !strings.contains(form.text, "e-") &&
           !strings.contains(form.text, "E-") {
            return 0, false
        }
        value, parsed := strconv.parse_f64(form.text)
        if !parsed {
            return 0, false
        }
        index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = .F64_Literal,
            value = {
                kind = .F64,
                constant = true,
                float_value = value,
            },
            span = form.span,
        })
        return index, true
    }
    value, parsed := repl_plan_parse_int(form.text)
    if !parsed {
        return 0, false
    }
    index := semantic_append_expr(analyzer, Semantic_Expr{
        kind = .Int_Literal,
        value = {
            kind = .Int,
            constant = true,
            int_value = value,
        },
        span = form.span,
    })
    return index, true
}


semantic_resident_scalar_invoke :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    resolved_name: string,
    proc_decl: ^Proc_Decl,
) -> (Repl_Scalar_Invoke_Metadata, Semantic_Value_Kind, bool) {
    // A loaded adapter preserves the already-compiled procedure's exact
    // native semantics, including state and effects. Stale session procedures
    // are excluded until their dependent definitions have been refreshed.
    if proc_decl == nil || !repl_proc_supports_scalar_invoke(proc_decl) ||
       contains_text(analyzer.stale_proc_names, resolved_name) {
        return {}, .Invalid, false
    }
    return_kind := semantic_value_kind_for_type(
        proc_decl.returns.single_ty,
    )
    if return_kind == .Invalid {
        return {}, .Invalid, false
    }
    for param in proc_decl.params {
        if semantic_value_kind_for_type(param.ty) == .Invalid {
            return {}, .Invalid, false
        }
    }
    signature := repl_proc_signature(proc_decl, analyzer.emitter)
    defer delete(signature)
    inferred_signature := semantic_inferred_scalar_signature(
        proc_decl,
    )
    defer delete(inferred_signature)
    borrowed_result_signature := ""
    owned_result_signature := ""
    if return_kind == .String || return_kind == .Data {
        borrowed_result_signature = semantic_inferred_scalar_signature(
            proc_decl,
            "borrowed",
        )
        owned_result_signature = semantic_inferred_scalar_signature(
            proc_decl,
            "owned",
        )
    }
    defer delete(borrowed_result_signature)
    defer delete(owned_result_signature)
    expected_result_abi := "value:bool"
    switch return_kind {
    case .Bool: expected_result_abi = "value:bool"
    case .Int:  expected_result_abi = "value:int"
    case .F64:  expected_result_abi = "value:f64"
    case .String: expected_result_abi = "value:string"
    case .Data: expected_result_abi = "value:Data"
    case .Invalid: return {}, .Invalid, false
    }
    for invoke in analyzer.scalar_invokes {
        borrowed_managed_result := strings.has_suffix(
            invoke.signature,
            ")->string:borrowed",
        ) || strings.has_suffix(
            invoke.signature,
            ")->Data:borrowed",
        )
        owned_managed_result := strings.has_suffix(
            invoke.signature,
            ")->string:owned",
        ) || strings.has_suffix(
            invoke.signature,
            ")->Data:owned",
        )
        managed_return := return_kind == .String || return_kind == .Data
        ownership_compatible := !managed_return ||
            ((proc_decl.returns.single_ownership == .Owned ||
              proc_decl.owns_result) && owned_managed_result) ||
            ((proc_decl.returns.single_ownership == .Borrowed ||
              proc_decl.borrows_result) && borrowed_managed_result) ||
            (proc_decl.returns.single_ownership == .Default &&
             !proc_decl.owns_result && !proc_decl.borrows_result &&
             (borrowed_managed_result || owned_managed_result))
        if invoke.name == resolved_name &&
           (invoke.signature == signature ||
            invoke.signature == inferred_signature ||
            invoke.signature == borrowed_result_signature ||
            invoke.signature == owned_result_signature) &&
           invoke.result_abi == expected_result_abi &&
           ownership_compatible {
            return invoke, return_kind, true
        }
    }
    return {}, .Invalid, false
}

semantic_inferred_scalar_signature :: proc(
    proc_decl: ^Proc_Decl,
    result_ownership := "",
) -> string {
    // Semantic planning happens before the ordinary lifetime inference pass,
    // while resident adapter registrations describe the inferred native ABI.
    // A supported non-owned scalar parameter is inferred as borrowed. Build
    // the requested result-ownership shape here, then preserve the exact
    // registered signature in the emitted plan for the worker's identity
    // check.
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    if proc_decl.calling_convention != "" {
        fmt.sbprintf(&builder, "abi=%s;", proc_decl.calling_convention)
    }
    strings.write_string(&builder, "proc(")
    for param, index in proc_decl.params {
        if index > 0 {
            strings.write_byte(&builder, ',')
        }
        strings.write_string(&builder, param.ty)
        strings.write_string(&builder, ":borrowed")
        if param.owner_flag != "" {
            fmt.sbprintf(&builder, ":owner=%s", param.owner_flag)
        }
    }
    strings.write_string(&builder, ")->")
    strings.write_string(&builder, proc_decl.returns.single_ty)
    if result_ownership != "" {
        strings.write_byte(&builder, ':')
        strings.write_string(&builder, result_ownership)
    } else if proc_decl.returns.single_ownership == .Owned ||
       proc_decl.owns_result {
        strings.write_string(&builder, ":owned")
    } else if proc_decl.returns.single_ownership == .Borrowed ||
              proc_decl.borrows_result {
        strings.write_string(&builder, ":borrowed")
    }
    return strings.clone(strings.to_string(builder))
}

semantic_analyze_proc_call :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    form: CST_Form,
    expected_kind: Semantic_Value_Kind,
) -> (int, bool) {
    if form.kind != .List || len(form.items) == 0 ||
       form.items[0].kind != .Symbol {
        return 0, false
    }
    resolved_name, proc_decl, resolved := resolve_proc_call_decl(
        analyzer.emitter,
        form.items[0].text,
    )
    if !resolved {
        delete(resolved_name)
        return 0, false
    }
    keep_resolved_name := false
    defer {
        if !keep_resolved_name {
            delete(resolved_name)
        }
    }
    program_call := contains_text(
        analyzer.program_proc_names,
        resolved_name,
    )
    invoke := Repl_Scalar_Invoke_Metadata{}
    return_kind := Semantic_Value_Kind.Invalid
    invoke_ok := false
    if program_call && proc_decl != nil &&
       repl_proc_supports_scalar_invoke(proc_decl) {
        return_kind = semantic_value_kind_for_type(
            proc_decl.returns.single_ty,
        )
        invoke_ok = return_kind != .Invalid
        for param in proc_decl.params {
            if semantic_value_kind_for_type(param.ty) == .Invalid {
                invoke_ok = false
                break
            }
        }
        if invoke_ok {
            invoke.signature = semantic_inferred_scalar_signature(proc_decl)
        }
    } else {
        invoke, return_kind, invoke_ok =
            semantic_resident_scalar_invoke(
                analyzer,
                resolved_name,
                proc_decl,
            )
    }
    defer if program_call {
        delete(invoke.signature)
    }
    if !invoke_ok || len(form.items)-1 != len(proc_decl.params) ||
       (expected_kind != .Invalid && expected_kind != return_kind) {
        return 0, false
    }
    argument_exprs: [dynamic]int
    defer delete(argument_exprs)
    for argument, index in form.items[1:] {
        param_kind := semantic_value_kind_for_type(
            proc_decl.params[index].ty,
        )
        argument_expr, analyzed := semantic_analyze_expr(
            analyzer,
            argument,
            param_kind,
        )
        if !analyzed ||
           analyzer.ir.expressions[argument_expr].value.kind != param_kind {
            return 0, false
        }
        append(&argument_exprs, argument_expr)
    }
    expression_index := semantic_append_expr(analyzer, Semantic_Expr{
        kind = .Program_Call if program_call else .Resident_Call,
        value = {
            kind = return_kind,
            managed_handle = return_kind == .Data,
        },
        span = form.span,
        resolved_name = resolved_name,
        scalar_signature = strings.clone(invoke.signature),
    }, argument_exprs[:])
    keep_resolved_name = true
    return expression_index, true
}

semantic_analyze_expr :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    form: CST_Form,
    expected_kind := Semantic_Value_Kind.Invalid,
) -> (int, bool) {
    if form.kind == .String || form.kind == .Number || form.kind == .Bool {
        return semantic_literal_expr(analyzer, form, expected_kind)
    }
    if form.kind == .Symbol {
        mapped_name := map_name(form.text)
        defer delete(mapped_name)
        for index := len(analyzer.locals); index > 0; {
            index -= 1
            local := analyzer.locals[index]
            if local.name == mapped_name {
                expr_index := semantic_append_expr(analyzer, Semantic_Expr{
                    kind = .Local,
                    value = local.value,
                    span = form.span,
                    operand = local.slot,
                })
                return expr_index, true
            }
        }
        result_index, recent := repl_plan_recent_result_index(form.text)
        if !recent || result_index >= len(analyzer.recent_result_types) {
            return 0, false
        }
        kind := semantic_value_kind_for_type(
            analyzer.recent_result_types[result_index],
        )
        if kind == .Invalid {
            return 0, false
        }
        expr_index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = .Recent_Result,
            value = {kind = kind},
            span = form.span,
            operand = result_index,
        })
        return expr_index, true
    }
    if form.kind != .List || len(form.items) == 0 ||
       form.items[0].kind != .Symbol {
        return 0, false
    }
    operator, operator_ok :=
        semantic_resolve_operator(analyzer, form.items[0].text)
    if !operator_ok {
        return 0, false
    }
    operands := form.items[1:]
    if operator == "return" || operator == "do" {
        return 0, false
    }
    if operator == "let" {
        if len(operands) != 2 || operands[0].kind != .Vector {
            return 0, false
        }
        bindings, _, parsed_bindings := parse_let_bindings(operands[0])
        if !parsed_bindings {
            return 0, false
        }
        defer delete(bindings)
        scope_start := len(analyzer.locals)
        defer resize(&analyzer.locals, scope_start)
        push_local_type_scope(analyzer.emitter)
        defer pop_local_type_scope(analyzer.emitter)
        semantic_bindings: [dynamic]Semantic_Binding
        defer delete(semantic_bindings)
        for binding in bindings {
            if binding.is_destructure || binding.is_result_binding ||
               binding.name == "" ||
               binding.err_deferred_delete ||
               binding.defer_with_cleanup ||
               repl_plan_operator_supported(binding.name) {
                return 0, false
            }
            for local in analyzer.locals {
                if local.name == binding.name {
                    return 0, false
                }
            }
            binding_kind := Semantic_Value_Kind.Invalid
            binding_type := ""
            if binding.is_typed {
                binding_type = binding.ty
                binding_kind = semantic_value_kind_for_type(binding.ty)
                if binding_kind == .Invalid {
                    return 0, false
                }
            } else if inferred_type, inferred :=
                obvious_binding_type(analyzer.emitter, binding); inferred {
                binding_type = inferred_type
                binding_kind =
                    semantic_value_kind_for_type(inferred_type)
            }
            value_expr, analyzed := semantic_analyze_expr(
                analyzer,
                binding.value,
                binding_kind,
            )
            if !analyzed {
                return 0, false
            }
            value := analyzer.ir.expressions[value_expr].value
            if binding_kind != .Invalid && value.kind != binding_kind {
                return 0, false
            }
            if binding_kind == .Invalid {
                binding_kind = value.kind
                binding_type = semantic_type_for_value_kind(binding_kind)
            }
            if binding_kind == .Invalid || binding_type == "" ||
               analyzer.next_local >= repl_plan.MAX_INSTRUCTIONS {
                return 0, false
            }
            if binding.deferred_delete && binding_kind != .String {
                return 0, false
            }
            slot := analyzer.next_local
            analyzer.next_local += 1
            append(&semantic_bindings, Semantic_Binding{
                slot = slot,
                value_expr = value_expr,
                value_kind = binding_kind,
                managed_cleanup = binding.deferred_delete ||
                    binding_kind == .Data,
                span = binding.value.span,
            })
            append(&analyzer.locals, Repl_Semantic_Local{
                name = binding.name,
                slot = slot,
                value = {
                    kind = binding_kind,
                    constant = value.constant,
                    managed_handle = value.managed_handle,
                    int_value = value.int_value,
                    float_value = value.float_value,
                    bool_value = value.bool_value,
                },
            })
            append(&analyzer.local_kinds, binding_kind)
            bind_local_type(analyzer.emitter, binding.name, binding_type)
        }
        body_expr, body_ok := semantic_analyze_expr(
            analyzer,
            operands[1],
            expected_kind,
        )
        if !body_ok {
            return 0, false
        }
        bindings_start := len(analyzer.ir.bindings)
        append(&analyzer.ir.bindings, ..semantic_bindings[:])
        body_value := analyzer.ir.expressions[body_expr].value
        expr_index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = .Let,
            value = body_value,
            span = form.span,
            bindings_start = bindings_start,
            bindings_count = len(semantic_bindings),
            body = body_expr,
        })
        return expr_index, true
    }
    if operator == "not" {
        if len(operands) != 1 {
            return 0, false
        }
        operand, analyzed := semantic_analyze_expr(
            analyzer,
            operands[0],
            .Bool,
        )
        if !analyzed {
            return 0, false
        }
        value := analyzer.ir.expressions[operand].value
        if value.kind != .Bool {
            return 0, false
        }
        children := []int{operand}
        expr_index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = .Not,
            value = {
                kind = .Bool,
                constant = value.constant,
                bool_value = !value.bool_value if value.constant else false,
            },
            span = form.span,
        }, children)
        return expr_index, true
    }
    if operator == "and" || operator == "or" {
        if len(operands) < 2 {
            return 0, false
        }
        children: [dynamic]int
        defer delete(children)
        all_constant := true
        constant_value := operator == "and"
        for operand in operands {
            child, analyzed := semantic_analyze_expr(
                analyzer,
                operand,
                .Bool,
            )
            if !analyzed {
                return 0, false
            }
            value := analyzer.ir.expressions[child].value
            if value.kind != .Bool {
                return 0, false
            }
            append(&children, child)
            all_constant = all_constant && value.constant
            if value.constant {
                if operator == "and" {
                    constant_value = constant_value && value.bool_value
                } else {
                    constant_value = constant_value || value.bool_value
                }
            }
        }
        expr_index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = .And if operator == "and" else .Or,
            value = {
                kind = .Bool,
                constant = all_constant,
                bool_value = constant_value if all_constant else false,
            },
            span = form.span,
        }, children[:])
        return expr_index, true
    }
    if operator == "if" {
        if len(operands) != 3 {
            return 0, false
        }
        test_expr, test_ok := semantic_analyze_expr(
            analyzer,
            operands[0],
            .Bool,
        )
        if !test_ok {
            return 0, false
        }
        test := analyzer.ir.expressions[test_expr].value
        if test.kind != .Bool {
            return 0, false
        }
        then_expr, then_ok := semantic_analyze_expr(
            analyzer,
            operands[1],
            expected_kind,
        )
        if !then_ok {
            return 0, false
        }
        else_expr, else_ok := semantic_analyze_expr(
            analyzer,
            operands[2],
            expected_kind,
        )
        if !else_ok {
            return 0, false
        }
        then_value := analyzer.ir.expressions[then_expr].value
        else_value := analyzer.ir.expressions[else_expr].value
        if then_value.kind != else_value.kind {
            return 0, false
        }
        result := Semantic_Value{kind = then_value.kind}
        if test.constant {
            result = then_value if test.bool_value else else_value
        } else if then_value.kind == .Data {
            result.managed_handle =
                then_value.managed_handle && else_value.managed_handle
        }
        children := []int{test_expr, then_expr, else_expr}
        expr_index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = .If,
            value = result,
            span = form.span,
        }, children)
        return expr_index, true
    }
    if operator == "+" || operator == "-" ||
       operator == "*" || operator == "/" || operator == "%" {
        minimum := 2
        if operator == "-" {
            minimum = 1
        }
        if len(operands) < minimum {
            return 0, false
        }
        numeric_context := expected_kind
        if numeric_context == .Invalid {
            numeric_context = semantic_form_value_kind(analyzer, form)
        }
        if numeric_context != .Int && numeric_context != .F64 {
            numeric_context = .Invalid
        } else if !form_accepts_expected_numeric_type(
            analyzer.emitter,
            form,
            semantic_type_for_value_kind(numeric_context),
        ) {
            numeric_context = .Invalid
        }
        children: [dynamic]int
        defer delete(children)
        values: [dynamic]Semantic_Value
        defer delete(values)
        operand_kind := Semantic_Value_Kind.Invalid
        all_constant := true
        for operand in operands {
            child, analyzed := semantic_analyze_expr(
                analyzer,
                operand,
                numeric_context,
            )
            if !analyzed {
                return 0, false
            }
            value := analyzer.ir.expressions[child].value
            if (value.kind != .Int && value.kind != .F64) ||
               (operand_kind != .Invalid && value.kind != operand_kind) {
                return 0, false
            }
            operand_kind = value.kind
            append(&children, child)
            append(&values, value)
            all_constant = all_constant && value.constant
        }
        if operator == "%" && operand_kind != .Int {
            return 0, false
        }
        // Until resident plans carry matching panic boundaries, only dynamic
        // int division/modulo with statically safe divisors is eligible.
        if operand_kind == .Int &&
           (operator == "/" || operator == "%") &&
           !all_constant {
            for divisor in values[1:] {
                if !divisor.constant || divisor.int_value == 0 ||
                   (operator == "/" && divisor.int_value == -1) {
                    return 0, false
                }
            }
        }
        result := Semantic_Value{
            kind = operand_kind,
            constant = all_constant,
        }
        if operand_kind == .Int && all_constant {
            result.int_value = values[0].int_value
            arithmetic_ok := true
            if operator == "-" && len(values) == 1 {
                if result.int_value == min(int) {
                    arithmetic_ok = false
                } else {
                    result.int_value = -result.int_value
                }
            }
            for value in values[1:] {
                switch operator {
                case "+":
                    result.int_value, arithmetic_ok =
                        repl_plan_checked_add(
                            result.int_value,
                            value.int_value,
                        )
                case "-":
                    result.int_value, arithmetic_ok =
                        repl_plan_checked_subtract(
                            result.int_value,
                            value.int_value,
                        )
                case "*":
                    result.int_value, arithmetic_ok =
                        repl_plan_checked_multiply(
                            result.int_value,
                            value.int_value,
                        )
                case "/":
                    if value.int_value == 0 ||
                       (result.int_value == min(int) &&
                        value.int_value == -1) {
                        arithmetic_ok = false
                    } else {
                        result.int_value /= value.int_value
                    }
                case "%":
                    if value.int_value == 0 {
                        arithmetic_ok = false
                    } else if result.int_value == min(int) &&
                              value.int_value == -1 {
                        result.int_value = 0
                    } else {
                        result.int_value %= value.int_value
                    }
                }
                if !arithmetic_ok {
                    return 0, false
                }
            }
        } else if operand_kind == .F64 && all_constant {
            result.float_value = values[0].float_value
            if operator == "-" && len(values) == 1 {
                result.float_value = -result.float_value
            }
            for value in values[1:] {
                switch operator {
                case "+": result.float_value += value.float_value
                case "-": result.float_value -= value.float_value
                case "*": result.float_value *= value.float_value
                case "/":
                    if value.float_value == 0 {
                        return 0, false
                    }
                    result.float_value /= value.float_value
                }
            }
        }
        expr_kind := Semantic_Expr_Kind.Invalid
        switch operator {
        case "+": expr_kind = .Add
        case "-": expr_kind = .Subtract
        case "*": expr_kind = .Multiply
        case "/": expr_kind = .Divide
        case "%": expr_kind = .Modulo
        }
        expr_index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = expr_kind,
            value = result,
            span = form.span,
        }, children[:])
        return expr_index, true
    }
    if operator == "=" || operator == "==" ||
       operator == "!=" || operator == "<" ||
       operator == "<=" || operator == ">" || operator == ">=" {
        if len(operands) != 2 {
            return 0, false
        }
        left_expected := semantic_form_value_kind(analyzer, operands[1])
        right_expected := semantic_form_value_kind(analyzer, operands[0])
        left_expr, left_ok := semantic_analyze_expr(
            analyzer,
            operands[0],
            left_expected,
        )
        right_expr, right_ok := semantic_analyze_expr(
            analyzer,
            operands[1],
            right_expected,
        )
        if !left_ok || !right_ok {
            return 0, false
        }
        left := analyzer.ir.expressions[left_expr].value
        right := analyzer.ir.expressions[right_expr].value
        if left.kind != right.kind || left.kind == .Data ||
           ((operator == "<" || operator == "<=" ||
             operator == ">" || operator == ">=") &&
            left.kind != .Int && left.kind != .F64) {
            return 0, false
        }
        expr_kind := Semantic_Expr_Kind.Invalid
        switch operator {
        case "=", "==": expr_kind = .Equal
        case "!=":       expr_kind = .Not_Equal
        case "<":        expr_kind = .Less
        case "<=":       expr_kind = .Less_Equal
        case ">":        expr_kind = .Greater
        case ">=":       expr_kind = .Greater_Equal
        }
        result := Semantic_Value{
            kind = .Bool,
            constant =
                left.constant && right.constant &&
                left.kind != .String,
        }
        if result.constant {
            if left.kind == .Bool {
                result.bool_value = left.bool_value == right.bool_value
                if operator == "!=" {
                    result.bool_value = !result.bool_value
                }
            } else if left.kind == .Int {
                switch operator {
                case "=", "==":
                    result.bool_value = left.int_value == right.int_value
                case "!=":
                    result.bool_value = left.int_value != right.int_value
                case "<":
                    result.bool_value = left.int_value < right.int_value
                case "<=":
                    result.bool_value = left.int_value <= right.int_value
                case ">":
                    result.bool_value = left.int_value > right.int_value
                case ">=":
                    result.bool_value = left.int_value >= right.int_value
                }
            } else {
                switch operator {
                case "=", "==":
                    result.bool_value =
                        left.float_value == right.float_value
                case "!=":
                    result.bool_value =
                        left.float_value != right.float_value
                case "<":
                    result.bool_value =
                        left.float_value < right.float_value
                case "<=":
                    result.bool_value =
                        left.float_value <= right.float_value
                case ">":
                    result.bool_value =
                        left.float_value > right.float_value
                case ">=":
                    result.bool_value =
                        left.float_value >= right.float_value
                }
            }
        }
        children := []int{left_expr, right_expr}
        expr_index := semantic_append_expr(analyzer, Semantic_Expr{
            kind = expr_kind,
            value = result,
            span = form.span,
        }, children)
        return expr_index, true
    }
    return semantic_analyze_proc_call(analyzer, form, expected_kind)
}

repl_analyze_semantic_expression :: proc(
    emitter: ^Emitter,
    form: CST_Form,
    recent_result_types: []string = nil,
    stale_proc_names: []string = nil,
    scalar_invokes: []Repl_Scalar_Invoke_Metadata = nil,
) -> (Semantic_Expression_IR, bool) {
    analyzer := Repl_Semantic_Analyzer{
        emitter = emitter,
        recent_result_types = recent_result_types,
        stale_proc_names = stale_proc_names,
        scalar_invokes = scalar_invokes,
    }
    defer delete(analyzer.locals)
    defer delete(analyzer.local_kinds)
    expected_kind := semantic_form_value_kind(&analyzer, form)
    if expected_kind == .Invalid && form.kind == .List &&
       len(form.items) > 0 && form.items[0].kind == .Symbol {
        if operator, resolved :=
               semantic_resolve_operator(&analyzer, form.items[0].text);
           resolved &&
           (operator == "not" || operator == "and" || operator == "or" ||
            operator == "=" || operator == "==" || operator == "!=" ||
            operator == "<" || operator == "<=" || operator == ">" ||
            operator == ">=") {
            expected_kind = .Bool
        }
    }
    if expected_kind == .Invalid &&
       (form.kind != .List || len(form.items) == 0 ||
        form.items[0].kind != .Symbol ||
        form.items[0].text != "let") {
        semantic_expression_ir_delete(&analyzer.ir)
        return {}, false
    }
    result_expr, analyzed := semantic_analyze_expr(
        &analyzer,
        form,
        expected_kind,
    )
    if !analyzed || result_expr < 0 ||
       result_expr >= len(analyzer.ir.expressions) ||
       analyzer.ir.expressions[result_expr].value.kind == .Invalid ||
       (expected_kind != .Invalid &&
        analyzer.ir.expressions[result_expr].value.kind != expected_kind) {
        semantic_expression_ir_delete(&analyzer.ir)
        return {}, false
    }
    analyzer.ir.result_expr = result_expr
    return analyzer.ir, true
}

repl_emit_semantic_expr :: proc(
    ir: Semantic_Expression_IR,
    builder: ^Repl_Plan_Builder,
    expression_index: int,
) -> bool {
    if expression_index < 0 || expression_index >= len(ir.expressions) {
        return false
    }
    expression := ir.expressions[expression_index]
    children_end := expression.children_start+expression.children_count
    if expression.children_start < 0 || expression.children_count < 0 ||
       children_end > len(ir.child_indices) {
        return false
    }
    children := ir.child_indices[expression.children_start:children_end]
    switch expression.kind {
    case .Bool_Literal:
        repl_plan_append(
            builder,
            .Push_Bool,
            1 if expression.value.bool_value else 0,
        )
    case .Int_Literal:
        repl_plan_append(builder, .Push_Int, expression.value.int_value)
    case .F64_Literal:
        bits := transmute(i64)expression.value.float_value
        repl_plan_append(builder, .Push_F64, int(bits))
    case .String_Literal:
        repl_plan_append_text(builder, .Push_String, expression.string_value)
    case .Recent_Result:
        repl_plan_append(builder, .Load_Result, expression.operand)
    case .Local:
        repl_plan_append(builder, .Load_Local, expression.operand)
    case .Let:
        bindings_end := expression.bindings_start+expression.bindings_count
        if expression.bindings_start < 0 || expression.bindings_count < 0 ||
           bindings_end > len(ir.bindings) {
            return false
        }
        for binding in ir.bindings[expression.bindings_start:bindings_end] {
            if !repl_emit_semantic_expr(
                ir,
                builder,
                binding.value_expr,
            ) {
                return false
            }
            repl_plan_append(builder, .Store_Local, binding.slot)
        }
        return repl_emit_semantic_expr(
            ir,
            builder,
            expression.body,
        )
    case .Resident_Call:
        if len(children) > 4 {
            return false
        }
        for child in children {
            if !repl_emit_semantic_expr(ir, builder, child) {
                return false
            }
        }
        opcode := repl_plan.Opcode.Invalid
        switch len(children) {
        case 0: opcode = .Invoke_Scalar_0
        case 1: opcode = .Invoke_Scalar_1
        case 2: opcode = .Invoke_Scalar_2
        case 3: opcode = .Invoke_Scalar_3
        case 4: opcode = .Invoke_Scalar_4
        case:   return false
        }
        target := strings.builder_make()
        defer strings.builder_destroy(&target)
        strings.write_string(&target, expression.resolved_name)
        strings.write_byte(&target, 0)
        strings.write_string(&target, expression.scalar_signature)
        repl_plan_append_text(
            builder,
            opcode,
            strings.to_string(target),
        )
    case .Program_Call, .Sequence, .Discard, .Set_Local, .While,
         .Return, .Break, .Continue:
        // Program calls belong to the backend-neutral incremental program.
        // Structured procedure control also belongs to that program. The
        // bounded resident-plan protocol never embeds procedure bodies.
        return false
    case .Not:
        if len(children) != 1 ||
           !repl_emit_semantic_expr(
               ir,
               builder,
               children[0],
           ) {
            return false
        }
        repl_plan_append(builder, .Not)
    case .And, .Or:
        if len(children) < 2 {
            return false
        }
        jumps: [dynamic]int
        defer delete(jumps)
        for child, index in children {
            if !repl_emit_semantic_expr(
                ir,
                builder,
                child,
            ) {
                return false
            }
            if index+1 < len(children) {
                jump := repl_plan_append(
                    builder,
                    .Short_False if expression.kind == .And else .Short_True,
                )
                append(&jumps, jump)
            }
        }
        end := len(builder.plan.instructions)
        for jump in jumps {
            builder.plan.instructions[jump].operand = end
        }
    case .If:
        if len(children) != 3 ||
           !repl_emit_semantic_expr(
               ir,
               builder,
               children[0],
           ) {
            return false
        }
        branch := repl_plan_append(builder, .Branch_False)
        if !repl_emit_semantic_expr(
            ir,
            builder,
            children[1],
        ) {
            return false
        }
        jump := repl_plan_append(builder, .Jump)
        builder.plan.instructions[branch].operand =
            len(builder.plan.instructions)
        if !repl_emit_semantic_expr(
            ir,
            builder,
            children[2],
        ) {
            return false
        }
        builder.plan.instructions[jump].operand =
            len(builder.plan.instructions)
    case .Add, .Subtract, .Multiply, .Divide, .Modulo:
        if len(children) == 0 {
            return false
        }
        for child in children {
            if !repl_emit_semantic_expr(
                ir,
                builder,
                child,
            ) {
                return false
            }
        }
        opcode := repl_plan.Opcode.Invalid
        #partial switch expression.kind {
        case .Add:      opcode = .Add
        case .Subtract: opcode = .Subtract
        case .Multiply: opcode = .Multiply
        case .Divide:   opcode = .Divide
        case .Modulo:   opcode = .Modulo
        case:
        }
        repl_plan_append(builder, opcode, len(children))
    case .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
        if len(children) != 2 {
            return false
        }
        for child in children {
            if !repl_emit_semantic_expr(
                ir,
                builder,
                child,
            ) {
                return false
            }
        }
        opcode := repl_plan.Opcode.Invalid
        #partial switch expression.kind {
        case .Equal:         opcode = .Equal
        case .Not_Equal:     opcode = .Not_Equal
        case .Less:          opcode = .Less
        case .Less_Equal:    opcode = .Less_Equal
        case .Greater:       opcode = .Greater
        case .Greater_Equal: opcode = .Greater_Equal
        case:
        }
        repl_plan_append(builder, opcode)
    case .Invalid:
        return false
    }
    return true
}
