package odinl

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
    R_Brace,
    Discard,
    Line_Comment,
    Block_Comment,
    String,
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
    String,
    Number,
    Bool,
    Nil,
    Symbol,
    Keyword,
}

CST_Form :: struct {
    kind:  CST_Form_Kind,
    text:  string,
    items: [dynamic]CST_Form,
    span:  Span,
}

CST_Top_Form :: struct {
    form:      CST_Form,
    doc_lines: [dynamic]string,
    source:    string,
}

Param :: struct {
    name: string,
    ty:   string,
}

Struct_Field :: struct {
    name: string,
    ty:   string,
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
    alias:     string,
    path:      string,
    has_alias: bool,
}

Struct_Decl :: struct {
    name:   string,
    fields: [dynamic]Struct_Field,
}

Const_Decl :: struct {
    name:   string,
    has_ty: bool,
    ty:     string,
    value:  CST_Form,
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
    params:            [dynamic]Param,
    returns:           Return_Spec,
    prefix_directives: [dynamic]string,
    suffix_directives: [dynamic]string,
    body:              [dynamic]CST_Form,
}

AST_Decl_Kind :: enum {
    Ignored,
    Package,
    Import,
    Const,
    Struct,
    Enum,
    Union,
    Proc,
    Raw,
}

AST_Decl :: struct {
    kind:         AST_Decl_Kind,
    span:         Span,
    doc_lines:    [dynamic]string,
    package_name: string,
    import_decl:  Import_Decl,
    const_decl:   Const_Decl,
    struct_decl:  Struct_Decl,
    enum_decl:    Enum_Decl,
    union_decl:   Union_Decl,
    proc_decl:    Proc_Decl,
    raw_text:     string,
}

IR_Decl :: AST_Decl

AST_Program :: struct {
    decls: [dynamic]AST_Decl,
}

IR_Program :: struct {
    decls: [dynamic]IR_Decl,
}

Source_Map_Entry :: struct {
    generated_start_line: int,
    generated_end_line:   int,
    source_span:          Span,
}

Emit_Result :: struct {
    output:     string,
    source_map: [dynamic]Source_Map_Entry,
}

Compile_Error :: struct {
    message: string,
    span:    Span,
}
