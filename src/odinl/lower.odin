package odinl

validate_top_level_order :: proc(program: AST_Program) -> (Compile_Error, bool) {
    seen_package := false
    seen_non_import_decl := false

    for decl in program.decls {
        #partial switch decl.kind {
        case .Package:
            if seen_package {
                return Compile_Error{message = "package declaration must appear exactly once", span = decl.span}, false
            }
            if seen_non_import_decl {
                return Compile_Error{message = "package declaration must be the first declaration", span = decl.span}, false
            }
            seen_package = true
        case .Import:
            if !seen_package {
                return Compile_Error{message = "import requires a preceding package declaration", span = decl.span}, false
            }
            if seen_non_import_decl {
                return Compile_Error{message = "import declarations must appear before other declarations", span = decl.span}, false
            }
        case:
            if !seen_package {
                return Compile_Error{message = "missing package declaration", span = decl.span}, false
            }
            seen_non_import_decl = true
        }
    }

    if !seen_package {
        return Compile_Error{message = "missing package declaration"}, false
    }
    return {}, true
}

lower_program :: proc(program: AST_Program) -> (lowered: IR_Program, err: Compile_Error, ok: bool) {
    err_order, ok_order := validate_top_level_order(program)
    if !ok_order {
        return lowered, err_order, false
    }

    for decl in program.decls {
        append(&lowered.decls, IR_Decl(decl))
    }
    return lowered, {}, true
}
