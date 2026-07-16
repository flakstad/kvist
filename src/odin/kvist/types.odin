// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

Source_Kind :: enum {
    File,
    Eval,
}

Span :: struct {
    start:  int,
    end:    int,
    source: Source_Kind,
}

Token_Kind :: enum {
    EOF,
    L_Paren,
    R_Paren,
    L_Bracket,
    R_Bracket,
    L_Brace,
    L_Set_Brace,
    R_Brace,
    Discard,
    Quote,
    Quasiquote,
    Unquote,
    Splice,
    Line_Comment,
    String,
    Regex,
    Number,
    Bool,
    Nil,
    Symbol,
    Keyword,
}

Token :: struct {
    kind: Token_Kind,
    text: string,
    span: Span,
}

CST_Form_Kind :: enum {
    List,
    Vector,
    Brace,
    Set,
    String,
    Regex,
    Number,
    Bool,
    Nil,
    Symbol,
    Keyword,
}

CST_Form :: struct {
    kind:        CST_Form_Kind,
    text:        string,
    source_text: string,
    items:       [dynamic]CST_Form,
    span:        Span,
}

CST_Top_Form :: struct {
    form:      CST_Form,
    doc_lines: [dynamic]string,
    source:    string,
}

Param :: struct {
    name:          string,
    ty:            string,
    has_default:   bool,
    default_value: CST_Form,
}

Struct_Field :: struct {
    name:        string,
    source_name: string,
    ty:          string,
    is_using:    bool,
}

Union_Variant :: struct {
    name: string,
    ty:   string,
}

Named_Return :: struct {
    name: string,
    ty:   string,
}

Return_Kind :: enum {
    None,
    Single,
    Named,
}

Return_Spec :: struct {
    kind:      Return_Kind,
    single_ty: string,
    named:     [dynamic]Named_Return,
}

Import_Decl :: struct {
    alias:      string,
    path:       string,
    has_alias:  bool,
    has_refer:  bool,
    refer_names: [dynamic]string,
}

Struct_Decl :: struct {
    name:   string,
    fields: [dynamic]Struct_Field,
}

Const_Init_Kind :: enum {
    Auto,
    Static,
    Runtime,
}

Const_Decl :: struct {
    name:          string,
    has_ty:        bool,
    ty:            string,
    value:         CST_Form,
    init_kind:     Const_Init_Kind,
    is_type_alias: bool,
    type_alias:    string,
    is_overload:   bool,
    overload_members: [dynamic]string,
}

Var_Decl :: struct {
    name:      string,
    has_ty:    bool,
    ty:        string,
    has_value: bool,
    value:     CST_Form,
}

Enum_Variant :: struct {
    name:      string,
    has_value: bool,
    value:     CST_Form,
}

Enum_Decl :: struct {
    name:     string,
    variants: [dynamic]Enum_Variant,
}

Union_Decl :: struct {
    name:     string,
    variants: [dynamic]Union_Variant,
}

Proc_Decl :: struct {
    name:              string,
    calling_convention: string,
    params:            [dynamic]Param,
    returns:           Return_Spec,
    owns_result:       bool,
    borrows_result:    bool,
    prefix_directives: [dynamic]string,
    suffix_directives: [dynamic]string,
    where_constraints: [dynamic]CST_Form,
    body:              [dynamic]CST_Form,
}

Transform_Decl :: struct {
    name: string,
    spec: CST_Form,
}

Source_Decl :: struct {
    name:        string,
    params:      [dynamic]Param,
    state_ty:    string,
    item_ty:     string,
    body:        [dynamic]CST_Form,
    next_name:   string,
    dispose_name: string,
    has_dispose: bool,
}

AST_Decl_Kind :: enum {
    Ignored,
    Package,
    Import,
    Const,
    Var,
    Struct,
    Enum,
    Union,
    Proc,
    Transform,
    Source,
    Raw,
}

AST_Decl :: struct {
    kind:         AST_Decl_Kind,
    span:         Span,
    doc_lines:    [dynamic]string,
    package_name: string,
    import_decl:  Import_Decl,
    const_decl:   Const_Decl,
    var_decl:     Var_Decl,
    struct_decl:  Struct_Decl,
    enum_decl:    Enum_Decl,
    union_decl:   Union_Decl,
    proc_decl:      Proc_Decl,
    transform_decl: Transform_Decl,
    source_decl:    Source_Decl,
    raw_text:       string,
}

IR_Decl :: AST_Decl

AST_Program :: struct {
    decls: [dynamic]AST_Decl,
}

IR_Program :: struct {
    decls: [dynamic]IR_Decl,
}

Source_Map_Entry :: struct {
    generated_start_line:   int,
    generated_end_line:     int,
    generated_start_column: int,
    generated_end_column:   int,
    source_span:            Span,
}

Emit_Result :: struct {
    output:     string,
    source_map: [dynamic]Source_Map_Entry,
    warnings:   [dynamic]Compile_Warning,
}

Compile_Error :: struct {
    message: string,
    span:    Span,
}

Compile_Warning :: struct {
    message: string,
    span:    Span,
}

Builtin_Macro_Kind :: enum {
    None,
    With_Allocator,
    With_Temp_Allocator,
}
