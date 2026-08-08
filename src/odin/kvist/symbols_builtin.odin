// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "base:runtime"

Imported_Symbol_Entry :: struct {
    alias: string,
    path:  string,
}

Imported_Symbol_Record :: struct {
    name:   string,
    record: string,
    rank:   int,
}

Local_Type_Binding :: struct {
    name: string,
    ty:   string,
}

Builtin_Source_Entry :: struct {
    name:     string,
    relative: string,
    snippet:  string,
}

Language_Source_Entry :: struct {
    name:     string,
    kind:     string,
    relative: string,
    snippet:  string,
}

BUILTIN_SOURCE_ENTRIES :: []Builtin_Source_Entry{
    {name = "type", relative = "src/odin/kvist/parse.odin", snippet = "if is_symbol(form.items[0], \"type\")"},
}

LANGUAGE_SOURCE_ENTRIES :: []Language_Source_Entry{
    {name = "package", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "case \"package\":"},
    {name = "import", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "case \"import\":"},
    {name = "def", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "case \"def\", \"def-\":"},
    {name = "defvar", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "case \"defvar\", \"defvar-\":"},
    {name = "defstruct", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "case \"defstruct\", \"defstruct-\":"},
    {name = "defenum", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "case \"defenum\", \"defenum-\":"},
    {name = "defunion", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "case \"defunion\", \"defunion-\":"},
    {name = "defn", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "case \"defn\", \"defn-\":"},
    {name = "defmacro", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "case \"defmacro\", \"defmacro-\":"},
    {name = "defiter", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "case \"defiter\", \"defiter-\":"},
    {name = "@export", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "@export"},
    {name = "@private", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "@private"},
    {name = "@exports", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "@exports [Name ...]"},
    {name = "fn", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "emit_proc_literal_expr :: proc"},
    {name = "odin", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"odin\":"},
    {name = "let", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"let\":"},
    {name = "block", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"do\", \"block\":"},
    {name = "do", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"do\":"},
    {name = "if", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "emit_if_like :: proc"},
    {name = "match", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "emit_match_stmt :: proc"},
    {name = "set!", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"set!\":"},
    {name = "mut!", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"mut!\":"},
    {name = "inc!", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"inc!\", \"dec!\", \"toggle!\", \"negate!\":"},
    {name = "dec!", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"inc!\", \"dec!\", \"toggle!\", \"negate!\":"},
    {name = "toggle!", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"inc!\", \"dec!\", \"toggle!\", \"negate!\":"},
    {name = "negate!", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"inc!\", \"dec!\", \"toggle!\", \"negate!\":"},
    {name = "return", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"return\":"},
    {name = "discard", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "(discard expr...)"},
    {name = "defer", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"defer\":"},
    {name = "for", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"for\":"},
    {name = "make", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "if head.text == \"make\""},
    {name = "type", kind = "kvist form", relative = "src/odin/kvist/parse.odin", snippet = "if is_symbol(form.items[0], \"type\")"},
    {name = "deref", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "if head.text == \"^\" || head.text == \"deref\""},
    {name = "addr", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "if head.text == \"&\" || head.text == \"addr\""},
    {name = "break", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"break\":"},
    {name = "continue", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"continue\":"},
    {name = "while", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "case \"while\":"},
    {name = "with-allocator", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "emit_with_allocator_stmt :: proc"},
    {name = "with-temp-allocator", kind = "kvist form", relative = "src/odin/kvist/emit.odin", snippet = "emit_with_temp_allocator_stmt :: proc"},
}

import_path_text :: proc(form: CST_Form) -> string {
    if form.kind != .String {
        return ""
    }
    return unquote_string(form.text)
}

builtin_symbols_write_entry :: proc(builder: ^strings.Builder, kind, name, signature, doc: string) {
    doc_lines := symbols_doc_lines_from_string(doc)
    defer delete(doc_lines)
    symbols_write_record_doc(builder, kind, name, "", Span{start = 0, end = 0, source = .File}, "", signature, doc_lines[:])
}

builtin_symbols_append :: proc(builder: ^strings.Builder) {
    builtin_symbols_write_entry(builder, "kvist form", "type", "(type Head Arg...)", "Instantiate an Odin polymorphic type constructor. For example, (type chan.Chan int) lowers to chan.Chan(int) in both type and value positions.")
}

builtin_symbols_source :: proc() -> string {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")
    builtin_symbols_append(&builder)
    return strings.clone(strings.to_string(builder), result_allocator)
}

language_symbols_source :: proc() -> string {
    result_allocator := context.allocator
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")
    for entry in LANGUAGE_SOURCE_ENTRIES {
        symbols_write_record_doc(&builder, entry.kind, entry.name, entry.relative, Span{start = 0, end = 0, source = .File}, "", "", nil)
    }
    return strings.clone(strings.to_string(builder), result_allocator)
}
