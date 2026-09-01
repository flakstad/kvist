package kvist

import "core:strings"
import repl_program "../kvist_repl_program"

// Repl_Incremental_Program is a checked, backend-neutral program rather than
// executable bytecode. The resident worker may lower it to native code, but
// an unavailable or unsupported backend leaves the ordinary Odin generation
// path unchanged.
Repl_Incremental_Program :: struct {
    encoded: string,
}

repl_incremental_program_delete :: proc(program: ^Repl_Incremental_Program) {
    if program == nil {
        return
    }
    delete(program.encoded)
    program^ = {}
}

semantic_value_kind_to_program_kind :: proc(
    kind: Semantic_Value_Kind,
) -> repl_program.Value_Kind {
    switch kind {
    case .Bool:   return .Bool
    case .Int:    return .Int
    case .F64:    return .F64
    case .String: return .String
    case .Data:   return .Data
    case .Invalid:
    }
    return .Invalid
}

semantic_expr_kind_to_program_kind :: proc(
    kind: Semantic_Expr_Kind,
) -> repl_program.Expr_Kind {
    switch kind {
    case .Bool_Literal:   return .Bool_Literal
    case .Int_Literal:    return .Int_Literal
    case .F64_Literal:    return .F64_Literal
    case .String_Literal: return .String_Literal
    case .Recent_Result:  return .Recent_Result
    case .Local:          return .Local
    case .Let:            return .Let
    case .Resident_Call:  return .Native_Call
    case .Program_Call:   return .Program_Call
    case .Sequence:       return .Sequence
    case .Discard:        return .Discard
    case .Set_Local:      return .Set_Local
    case .While:          return .While
    case .Return:         return .Return
    case .Break:          return .Break
    case .Continue:       return .Continue
    case .If:             return .If
    case .Not:            return .Not
    case .And:            return .And
    case .Or:             return .Or
    case .Add:            return .Add
    case .Subtract:       return .Subtract
    case .Multiply:       return .Multiply
    case .Divide:         return .Divide
    case .Modulo:         return .Modulo
    case .Equal:          return .Equal
    case .Not_Equal:      return .Not_Equal
    case .Less:           return .Less
    case .Less_Equal:     return .Less_Equal
    case .Greater:        return .Greater
    case .Greater_Equal:  return .Greater_Equal
    case .Invalid:
    }
    return .Invalid
}

repl_incremental_native_expression_supported :: proc(
    expression: Semantic_Expr,
) -> bool {
    // This first native backend slice is deliberately a semantic class, not a
    // list of source functions: scalar values, immutable locals, structured
    // control flow, arithmetic, comparisons, and calls within the submitted
    // program. Calls through exact resident scalar adapters keep their
    // versioned native identity; managed values still need a lifecycle bridge.
    void_value := expression.value.kind == .Invalid &&
        (expression.kind == .Sequence || expression.kind == .Discard ||
         expression.kind == .Set_Local || expression.kind == .While ||
         expression.kind == .Return || expression.kind == .Break ||
         expression.kind == .Continue || expression.kind == .If)
    managed_value := expression.value.kind == .String ||
        expression.value.kind == .Data
    if managed_value {
        // Managed values are opaque temporaries owned by the worker frame.
        // They may be constructed by a literal or exact native adapter and
        // selected by structured expression flow and held in immutable let
        // locals, but cannot yet become JIT procedure parameters, results, or
        // mutable locals. A managed-valued let also stays native: its result
        // may outlive the lexical cleanup represented by the binding.
        return expression.kind == .String_Literal ||
               expression.kind == .Resident_Call ||
               expression.kind == .Sequence || expression.kind == .If ||
               expression.kind == .Local
    }
    if !void_value && expression.value.kind != .Bool &&
       expression.value.kind != .Int && expression.value.kind != .F64 {
        return false
    }
    #partial switch expression.kind {
    case .Bool_Literal, .Int_Literal, .F64_Literal,
         .Local, .Let, .Program_Call, .Sequence, .Discard,
         .Set_Local, .While, .Return, .Break, .Continue, .Resident_Call,
         .If, .Not, .And, .Or,
         .Add, .Subtract, .Multiply, .Divide, .Modulo,
         .Equal, .Not_Equal, .Less, .Less_Equal,
         .Greater, .Greater_Equal:
        return true
    case .Invalid, .String_Literal, .Recent_Result:
        return false
    }
    return false
}

repl_incremental_program_proc_eligible :: proc(
    proc_decl: ^Proc_Decl,
) -> bool {
    if proc_decl == nil || proc_decl.calling_convention != "" ||
       proc_decl.returns.kind != .Single || len(proc_decl.body) == 0 ||
       len(proc_decl.prefix_directives) != 0 ||
       len(proc_decl.suffix_directives) != 0 ||
       len(proc_decl.where_constraints) != 0 ||
       !repl_proc_is_concrete(proc_decl) {
        return false
    }
    result_kind := semantic_value_kind_for_type(proc_decl.returns.single_ty)
    if result_kind != .Bool && result_kind != .Int && result_kind != .F64 {
        return false
    }
    for param in proc_decl.params {
        kind := semantic_value_kind_for_type(param.ty)
        if (kind != .Bool && kind != .Int && kind != .F64) ||
           param.mutable || param.has_default || param.owner_flag != "" {
            return false
        }
    }
    return true
}

repl_incremental_program_proc_decl :: proc(
    program: AST_Program,
    name: string,
) -> ^Proc_Decl {
    for &decl in program.decls {
        if decl.kind == .Proc && decl.proc_decl.name == name {
            return &decl.proc_decl
        }
    }
    return nil
}

repl_incremental_expr_always_terminates :: proc(
    ir: ^Semantic_Expression_IR,
    expression_index: int,
) -> bool {
    if ir == nil || expression_index < 0 ||
       expression_index >= len(ir.expressions) {
        return false
    }
    expression := ir.expressions[expression_index]
    #partial switch expression.kind {
    case .Return, .Break, .Continue:
        return true
    case .Sequence:
        if expression.children_count == 0 {
            return false
        }
        last := ir.child_indices[
            expression.children_start+expression.children_count-1
        ]
        return repl_incremental_expr_always_terminates(ir, last)
    case .If:
        if expression.children_count != 3 {
            return false
        }
        then_expression := ir.child_indices[expression.children_start+1]
        else_expression := ir.child_indices[expression.children_start+2]
        return repl_incremental_expr_always_terminates(
                   ir,
                   then_expression,
               ) &&
               repl_incremental_expr_always_terminates(
                   ir,
                   else_expression,
               )
    case:
    }
    return false
}

repl_incremental_local :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    source_name: string,
) -> ^Repl_Semantic_Local {
    if analyzer == nil {
        return nil
    }
    mapped_name := map_name(source_name)
    defer delete(mapped_name)
    for index := len(analyzer.locals); index > 0; {
        index -= 1
        if analyzer.locals[index].name == mapped_name {
            return &analyzer.locals[index]
        }
    }
    return nil
}

repl_incremental_scoped_sequence :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    forms: []CST_Form,
    tail_kind := Semantic_Value_Kind.Invalid,
) -> (int, bool) {
    scope_start := len(analyzer.locals)
    push_local_type_scope(analyzer.emitter)
    result, ok := repl_incremental_sequence(analyzer, forms, tail_kind)
    pop_local_type_scope(analyzer.emitter)
    for index in scope_start..<len(analyzer.locals) {
        delete(analyzer.locals[index].name)
    }
    resize(&analyzer.locals, scope_start)
    return result, ok
}

repl_incremental_set_local :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    local: ^Repl_Semantic_Local,
    value_expr: int,
    span: Span,
) -> (int, bool) {
    if analyzer == nil || local == nil || !local.mutable ||
       value_expr < 0 || value_expr >= len(analyzer.ir.expressions) ||
       analyzer.ir.expressions[value_expr].value.kind != local.value.kind {
        return 0, false
    }
    local.value.constant = false
    child := []int{value_expr}
    return semantic_append_expr(analyzer, Semantic_Expr{
        kind = .Set_Local,
        span = span,
        operand = local.slot,
    }, child), true
}

repl_incremental_analyze_local_declaration :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    form: CST_Form,
) -> (int, bool) {
    if len(form.items) < 3 || form.items[1].kind != .Symbol {
        return 0, false
    }
    name, has_type, type_text, has_value, value_form, _, parsed :=
        parse_decl_typed_binding(form, "defvar", 2, true)
    if !parsed || !has_value || name == "" ||
       analyzer.next_local >= repl_program.MAX_EXPRESSIONS {
        delete(name)
        return 0, false
    }
    defer delete(name)
    for local in analyzer.locals {
        if local.name == name {
            return 0, false
        }
    }
    kind := Semantic_Value_Kind.Invalid
    if has_type {
        kind = semantic_value_kind_for_type(type_text)
    } else {
        kind = semantic_form_value_kind(analyzer, value_form)
    }
    value_expr, analyzed := semantic_analyze_expr(
        analyzer,
        value_form,
        kind,
    )
    if !analyzed {
        return 0, false
    }
    value := analyzer.ir.expressions[value_expr].value
    if kind == .Invalid {
        kind = value.kind
        type_text = semantic_type_for_value_kind(kind)
    }
    if kind == .Invalid || value.kind != kind || type_text == "" {
        return 0, false
    }
    slot := analyzer.next_local
    analyzer.next_local += 1
    append(&analyzer.locals, Repl_Semantic_Local{
        name = strings.clone(name),
        slot = slot,
        value = {kind = kind},
        mutable = true,
    })
    append(&analyzer.local_kinds, kind)
    bind_local_type(analyzer.emitter, name, type_text, mutable = true)
    return repl_incremental_set_local(
        analyzer,
        &analyzer.locals[len(analyzer.locals)-1],
        value_expr,
        form.span,
    )
}

repl_incremental_analyze_mutation :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    form: CST_Form,
    operator: string,
) -> (int, bool) {
    if len(form.items) != 2 || form.items[1].kind != .Symbol {
        return 0, false
    }
    local := repl_incremental_local(analyzer, form.items[1].text)
    if local == nil || !local.mutable {
        return 0, false
    }
    local_expr := semantic_append_expr(analyzer, Semantic_Expr{
        kind = .Local,
        value = {kind = local.value.kind},
        span = form.items[1].span,
        operand = local.slot,
    })
    value_expr := -1
    switch operator {
    case "toggle!":
        if local.value.kind != .Bool {
            return 0, false
        }
        child := []int{local_expr}
        value_expr = semantic_append_expr(analyzer, Semantic_Expr{
            kind = .Not,
            value = {kind = .Bool},
            span = form.span,
        }, child)
    case "inc!", "dec!", "negate!":
        if local.value.kind != .Int && local.value.kind != .F64 {
            return 0, false
        }
        children: [2]int
        child_count := 1
        children[0] = local_expr
        kind := Semantic_Expr_Kind.Subtract
        if operator != "negate!" {
            literal := Semantic_Expr{
                kind = .Int_Literal,
                value = {kind = .Int, constant = true, int_value = 1},
                span = form.span,
            }
            if local.value.kind == .F64 {
                literal.kind = .F64_Literal
                literal.value = {
                    kind = .F64,
                    constant = true,
                    float_value = 1,
                }
            }
            children[1] = semantic_append_expr(analyzer, literal)
            child_count = 2
            if operator == "inc!" {
                kind = .Add
            }
        }
        value_expr = semantic_append_expr(analyzer, Semantic_Expr{
            kind = kind,
            value = {kind = local.value.kind},
            span = form.span,
        }, children[:child_count])
    case:
        return 0, false
    }
    return repl_incremental_set_local(
        analyzer,
        local,
        value_expr,
        form.span,
    )
}

repl_incremental_analyze_if :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    form: CST_Form,
    tail_kind := Semantic_Value_Kind.Invalid,
) -> (int, bool) {
    if len(form.items) < 3 || len(form.items) > 4 {
        return 0, false
    }
    condition, condition_ok := semantic_analyze_expr(
        analyzer,
        form.items[1],
        .Bool,
    )
    if !condition_ok ||
       analyzer.ir.expressions[condition].value.kind != .Bool {
        return 0, false
    }
    then_forms := form.items[2:3]
    if form.items[2].kind == .List && len(form.items[2].items) > 0 &&
       form.items[2].items[0].kind == .Symbol &&
       form.items[2].items[0].text == "do" {
        then_forms = form.items[2].items[1:]
    }
    then_expr, then_ok := repl_incremental_scoped_sequence(
        analyzer,
        then_forms,
        tail_kind,
    )
    if !then_ok {
        return 0, false
    }
    else_expr := -1
    else_ok := false
    if len(form.items) == 4 {
        else_forms := form.items[3:4]
        if form.items[3].kind == .List &&
           len(form.items[3].items) > 0 &&
           form.items[3].items[0].kind == .Symbol &&
           form.items[3].items[0].text == "do" {
            else_forms = form.items[3].items[1:]
        }
        else_expr, else_ok = repl_incremental_scoped_sequence(
            analyzer,
            else_forms,
            tail_kind,
        )
    } else {
        else_expr, else_ok = repl_incremental_scoped_sequence(
            analyzer,
            nil,
        )
    }
    if !else_ok {
        return 0, false
    }
    value := Semantic_Value{}
    if tail_kind != .Invalid {
        then_value := analyzer.ir.expressions[then_expr].value.kind
        else_value := analyzer.ir.expressions[else_expr].value.kind
        then_valid := then_value == tail_kind ||
            repl_incremental_expr_always_terminates(&analyzer.ir, then_expr)
        else_valid := else_value == tail_kind ||
            repl_incremental_expr_always_terminates(&analyzer.ir, else_expr)
        if !then_valid || !else_valid ||
           (then_value != tail_kind && else_value != tail_kind) {
            return 0, false
        }
        value.kind = tail_kind
    }
    children := []int{condition, then_expr, else_expr}
    return semantic_append_expr(analyzer, Semantic_Expr{
        kind = .If,
        value = value,
        span = form.span,
    }, children), true
}

repl_incremental_analyze_form :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    form: CST_Form,
    tail_kind := Semantic_Value_Kind.Invalid,
) -> (int, bool) {
    head := ""
    if form.kind == .List && len(form.items) > 0 &&
       form.items[0].kind == .Symbol {
        resolved, ok := semantic_resolve_operator(
            analyzer,
            form.items[0].text,
        )
        if ok {
            head = resolved
        }
    }
    switch head {
    case "defvar":
        if tail_kind != .Invalid {
            return 0, false
        }
        return repl_incremental_analyze_local_declaration(analyzer, form)
    case "set!":
        if tail_kind != .Invalid || len(form.items) != 3 ||
           form.items[1].kind != .Symbol {
            return 0, false
        }
        local := repl_incremental_local(analyzer, form.items[1].text)
        if local == nil || !local.mutable {
            return 0, false
        }
        local_kind := local.value.kind
        value_expr, value_ok := semantic_analyze_expr(
            analyzer,
            form.items[2],
            local_kind,
        )
        if !value_ok {
            return 0, false
        }
        local = repl_incremental_local(analyzer, form.items[1].text)
        return repl_incremental_set_local(
            analyzer,
            local,
            value_expr,
            form.span,
        )
    case "inc!", "dec!", "toggle!", "negate!":
        if tail_kind != .Invalid {
            return 0, false
        }
        return repl_incremental_analyze_mutation(analyzer, form, head)
    case "discard":
        if tail_kind != .Invalid || len(form.items) < 2 {
            return 0, false
        }
        children: [dynamic]int
        defer delete(children)
        for operand in form.items[1:] {
            expected := semantic_form_value_kind(analyzer, operand)
            child, child_ok := semantic_analyze_expr(
                analyzer,
                operand,
                expected,
            )
            if !child_ok {
                return 0, false
            }
            append(&children, child)
        }
        return semantic_append_expr(analyzer, Semantic_Expr{
            kind = .Discard,
            span = form.span,
        }, children[:]), true
    case "do":
        return repl_incremental_scoped_sequence(
            analyzer,
            form.items[1:],
            tail_kind,
        )
    case "if":
        return repl_incremental_analyze_if(analyzer, form, tail_kind)
    case "while":
        if tail_kind != .Invalid || len(form.items) < 3 {
            return 0, false
        }
        condition, condition_ok := semantic_analyze_expr(
            analyzer,
            form.items[1],
            .Bool,
        )
        if !condition_ok ||
           analyzer.ir.expressions[condition].value.kind != .Bool {
            return 0, false
        }
        analyzer.loop_depth += 1
        body, body_ok := repl_incremental_scoped_sequence(
            analyzer,
            form.items[2:],
        )
        analyzer.loop_depth -= 1
        if !body_ok {
            return 0, false
        }
        children := []int{condition, body}
        return semantic_append_expr(analyzer, Semantic_Expr{
            kind = .While,
            span = form.span,
        }, children), true
    case "return":
        if len(form.items) != 2 ||
           analyzer.procedure_result_kind == .Invalid {
            return 0, false
        }
        value, value_ok := semantic_analyze_expr(
            analyzer,
            form.items[1],
            analyzer.procedure_result_kind,
        )
        if !value_ok || analyzer.ir.expressions[value].value.kind !=
           analyzer.procedure_result_kind {
            return 0, false
        }
        children := []int{value}
        return semantic_append_expr(analyzer, Semantic_Expr{
            kind = .Return,
            span = form.span,
        }, children), true
    case "break", "continue":
        if len(form.items) != 1 || analyzer.loop_depth <= 0 {
            return 0, false
        }
        return semantic_append_expr(analyzer, Semantic_Expr{
            kind = .Break if head == "break" else .Continue,
            span = form.span,
        }), true
    }

    expected := tail_kind
    if expected == .Invalid {
        expected = semantic_form_value_kind(analyzer, form)
    }
    expression, analyzed := semantic_analyze_expr(
        analyzer,
        form,
        expected,
    )
    if !analyzed {
        return 0, false
    }
    if tail_kind != .Invalid {
        if analyzer.ir.expressions[expression].value.kind != tail_kind {
            return 0, false
        }
        return expression, true
    }
    child := []int{expression}
    return semantic_append_expr(analyzer, Semantic_Expr{
        kind = .Discard,
        span = form.span,
    }, child), true
}

repl_incremental_sequence :: proc(
    analyzer: ^Repl_Semantic_Analyzer,
    forms: []CST_Form,
    tail_kind := Semantic_Value_Kind.Invalid,
) -> (int, bool) {
    children: [dynamic]int
    defer delete(children)
    for form, index in forms {
        expected := Semantic_Value_Kind.Invalid
        if index == len(forms)-1 {
            expected = tail_kind
        }
        child, child_ok := repl_incremental_analyze_form(
            analyzer,
            form,
            expected,
        )
        if !child_ok {
            return 0, false
        }
        append(&children, child)
    }
    value := Semantic_Value{}
    if tail_kind != .Invalid {
        if len(children) == 0 {
            return 0, false
        }
        last := children[len(children)-1]
        if analyzer.ir.expressions[last].value.kind == tail_kind {
            value.kind = tail_kind
        } else if !repl_incremental_expr_always_terminates(
            &analyzer.ir,
            last,
        ) {
            return 0, false
        }
    }
    return semantic_append_expr(analyzer, Semantic_Expr{
        kind = .Sequence,
        value = value,
    }, children[:]), true
}

repl_incremental_program_copy_procedure :: proc(
    ir: Semantic_Expression_IR,
    proc_decl: ^Proc_Decl,
    local_kinds: []Semantic_Value_Kind,
) -> (repl_program.Procedure, bool) {
    if proc_decl == nil || ir.result_expr < 0 ||
       ir.result_expr >= len(ir.expressions) {
        return {}, false
    }
    procedure := repl_program.Procedure{
        name = strings.clone(proc_decl.name),
        signature = semantic_inferred_scalar_signature(proc_decl),
        result_kind = semantic_value_kind_to_program_kind(
            semantic_value_kind_for_type(proc_decl.returns.single_ty),
        ),
        local_count = len(local_kinds),
        result_expr = ir.result_expr,
    }
    valid := procedure.result_kind != .Invalid
    for param in proc_decl.params {
        kind := semantic_value_kind_to_program_kind(
            semantic_value_kind_for_type(param.ty),
        )
        if kind == .Invalid {
            valid = false
            break
        }
        append(&procedure.parameter_kinds, kind)
    }
    for semantic_kind in local_kinds {
        kind := semantic_value_kind_to_program_kind(semantic_kind)
        if kind == .Invalid || kind == .Void {
            valid = false
            break
        }
        append(&procedure.local_kinds, kind)
    }
    if valid {
        for expression in ir.expressions {
            if !repl_incremental_native_expression_supported(expression) {
                valid = false
                break
            }
            if expression.kind == .Set_Local && expression.operand >= 0 &&
               expression.operand < len(local_kinds) &&
               (local_kinds[expression.operand] == .String ||
                local_kinds[expression.operand] == .Data) {
                valid = false
                break
            }
            value_kind := semantic_value_kind_to_program_kind(
                expression.value.kind,
            )
            if expression.value.kind == .Invalid {
                #partial switch expression.kind {
                case .Sequence, .Discard, .Set_Local, .While, .Return,
                     .Break, .Continue, .If:
                    value_kind = .Void
                case:
                }
            }
            append(&procedure.expressions, repl_program.Expression{
                kind = semantic_expr_kind_to_program_kind(expression.kind),
                value_kind = value_kind,
                operand = expression.operand,
                children_start = expression.children_start,
                children_count = expression.children_count,
                bindings_start = expression.bindings_start,
                bindings_count = expression.bindings_count,
                body = expression.body,
                int_value = expression.value.int_value,
                float_value = expression.value.float_value,
                bool_value = expression.value.bool_value,
                resolved_name = strings.clone(expression.resolved_name),
                scalar_signature = strings.clone(
                    expression.scalar_signature,
                ),
                string_value = strings.clone(expression.string_value),
            })
        }
    }
    if valid {
        append(&procedure.child_indices, ..ir.child_indices[:])
        for binding in ir.bindings {
            append(&procedure.bindings, repl_program.Binding{
                slot = binding.slot,
                value_expr = binding.value_expr,
                value_kind = semantic_value_kind_to_program_kind(
                    binding.value_kind,
                ),
                managed_cleanup = binding.managed_cleanup,
            })
        }
    }
    if valid {
        for binding in procedure.bindings {
            if !binding.managed_cleanup {
                continue
            }
            value_expression := &procedure.expressions[
                binding.value_expr
            ]
            cleanup_supported := value_expression.kind == .Native_Call &&
                value_expression.value_kind == binding.value_kind
            if binding.value_kind == .String {
                cleanup_supported = cleanup_supported &&
                    strings.has_suffix(
                        value_expression.scalar_signature,
                        ")->string:owned",
                    )
            } else if binding.value_kind == .Data {
                cleanup_supported = cleanup_supported &&
                    (strings.has_suffix(
                        value_expression.scalar_signature,
                        ")->Data:owned",
                    ) || strings.has_suffix(
                        value_expression.scalar_signature,
                        ")->Data:borrowed",
                    ))
            } else {
                cleanup_supported = false
            }
            if !cleanup_supported {
                valid = false
                break
            }
        }
    }
    if valid {
        for expression, expression_index in procedure.expressions {
            owned_managed_call := expression.kind == .Native_Call &&
                (expression.value_kind == .String ||
                 expression.value_kind == .Data) &&
                (strings.has_suffix(
                    expression.scalar_signature,
                    ")->string:owned",
                ) || strings.has_suffix(
                    expression.scalar_signature,
                    ")->Data:owned",
                ))
            if !owned_managed_call {
                continue
            }
            cleanup_bound := false
            for binding in procedure.bindings {
                if binding.value_expr == expression_index &&
                   binding.managed_cleanup {
                    cleanup_bound = true
                    break
                }
            }
            if !cleanup_bound {
                valid = false
                break
            }
        }
    }
    if !valid {
        repl_program.procedure_delete(&procedure)
        return {}, false
    }
    return procedure, true
}

repl_build_incremental_program :: proc(
    program: AST_Program,
    current_proc_names: []string,
    stale_proc_names: []string = nil,
    scalar_invokes: []Repl_Scalar_Invoke_Metadata = nil,
) -> (Repl_Incremental_Program, bool) {
    if len(current_proc_names) == 0 ||
       len(current_proc_names) > repl_program.MAX_PROCEDURES {
        return {}, false
    }
    features := Emitter_Features{}
    emitter := Emitter{
        decls = program.decls[:],
        features = &features,
        repl_current_proc_names = current_proc_names,
    }
    for decl in program.decls {
        if decl.kind == .Struct {
            append(&emitter.structs, decl.struct_decl)
        }
        if decl.kind == .Union {
            append(&emitter.unions, decl.union_decl)
        }
    }
    native_program := repl_program.Program{}
    defer repl_program.program_delete(&native_program)
    for name in current_proc_names {
        proc_decl := repl_incremental_program_proc_decl(program, name)
        if !repl_incremental_program_proc_eligible(proc_decl) {
            return {}, false
        }
        analyzer := Repl_Semantic_Analyzer{
            emitter = &emitter,
            stale_proc_names = stale_proc_names,
            scalar_invokes = scalar_invokes,
            program_proc_names = current_proc_names,
        }
        push_local_type_scope(&emitter)
        for param, index in proc_decl.params {
            mapped_name := map_name(param.name)
            kind := semantic_value_kind_for_type(param.ty)
            append(&analyzer.locals, Repl_Semantic_Local{
                name = mapped_name,
                slot = index,
                value = {kind = kind},
            })
            append(&analyzer.local_kinds, kind)
            bind_local_type(&emitter, mapped_name, param.ty)
        }
        analyzer.next_local = len(proc_decl.params)
        result_kind := semantic_value_kind_for_type(
            proc_decl.returns.single_ty,
        )
        analyzer.procedure_result_kind = result_kind
        result_expr, analyzed := repl_incremental_sequence(
            &analyzer,
            proc_decl.body[:],
            result_kind,
        )
        pop_local_type_scope(&emitter)
        for local in analyzer.locals {
            delete(local.name)
        }
        delete(analyzer.locals)
        if !analyzed || result_expr < 0 ||
           result_expr >= len(analyzer.ir.expressions) ||
           (analyzer.ir.expressions[result_expr].value.kind != result_kind &&
            !repl_incremental_expr_always_terminates(
                &analyzer.ir,
                result_expr,
            )) {
            delete(analyzer.local_kinds)
            semantic_expression_ir_delete(&analyzer.ir)
            return {}, false
        }
        analyzer.ir.result_expr = result_expr
        procedure, copied := repl_incremental_program_copy_procedure(
            analyzer.ir,
            proc_decl,
            analyzer.local_kinds[:],
        )
        delete(analyzer.local_kinds)
        semantic_expression_ir_delete(&analyzer.ir)
        if !copied {
            return {}, false
        }
        append(&native_program.procedures, procedure)
    }
    encoded, encoded_ok := repl_program.program_encode(native_program)
    if !encoded_ok {
        return {}, false
    }
    return Repl_Incremental_Program{encoded = encoded}, true
}
