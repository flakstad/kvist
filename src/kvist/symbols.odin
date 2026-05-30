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

Builtin_Source_Entry :: struct {
    name:     string,
    relative: string,
    snippet:  string,
}

Package_Source_Entry :: struct {
    import_path: string,
    member:      string,
    relative:    string,
    snippet:     string,
}

Language_Source_Entry :: struct {
    name:     string,
    kind:     string,
    relative: string,
    snippet:  string,
}

KVIST_CANONICAL_IMPORTS_FOR_EDITOR :: [5]Imported_Symbol_Entry{
    {alias = "arr", path = "kvist:arr"},
    {alias = "str", path = "kvist:str"},
    {alias = "map", path = "kvist:map"},
    {alias = "set", path = "kvist:set"},
    {alias = "struct", path = "kvist:struct"},
}

BUILTIN_SOURCE_ENTRIES :: []Builtin_Source_Entry{
    {name = "when-let", relative = "src/kvist/macroexpand.odin", snippet = "expand_when_let_form :: proc"},
    {name = "if-let", relative = "src/kvist/macroexpand.odin", snippet = "expand_if_let_form :: proc"},
    {name = "when-ok", relative = "src/kvist/macroexpand.odin", snippet = "expand_when_ok_form :: proc"},
    {name = "if-ok", relative = "src/kvist/macroexpand.odin", snippet = "expand_if_ok_form :: proc"},
    {name = "println", relative = "src/kvist/emit.odin", snippet = "if form.items[0].text == \"println\" || form.items[0].text == \"doc\""},
    {name = "doc", relative = "src/kvist/emit.odin", snippet = "case \"doc\":"},
    {name = "update!", relative = "src/kvist/emit.odin", snippet = "case \"update!\":"},
    {name = "update", relative = "src/kvist/emit.odin", snippet = "case \"update\":"},
    {name = "type", relative = "src/kvist/parse.odin", snippet = "if is_symbol(form.items[0], \"type\")"},
}

PACKAGE_SOURCE_ENTRIES :: []Package_Source_Entry{
    {import_path = "kvist:arr", member = "count", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/count\" || head.text == \"str/count\""},
    {import_path = "kvist:arr", member = "empty", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/empty\""},
    {import_path = "kvist:arr", member = "dynamic", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/dynamic\""},
    {import_path = "kvist:arr", member = "fixed", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/fixed\""},
    {import_path = "kvist:arr", member = "get", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/get\" || head.text == \"str/get\" || head.text == \"map/get\""},
    {import_path = "kvist:arr", member = "slice", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/slice\" || head.text == \"str/slice\""},
    {import_path = "kvist:arr", member = "push!", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/push!\""},
    {import_path = "kvist:arr", member = "map", relative = "src/kvist/emit.odin", snippet = "emit_core_map_helper :: proc"},
    {import_path = "kvist:arr", member = "filter", relative = "src/kvist/emit.odin", snippet = "emit_core_filter_helper :: proc"},
    {import_path = "kvist:arr", member = "map!", relative = "src/kvist/emit.odin", snippet = "emit_core_map_in_place_helper :: proc"},
    {import_path = "kvist:arr", member = "filter!", relative = "src/kvist/emit.odin", snippet = "emit_core_filter_in_place_helper :: proc"},
    {import_path = "kvist:arr", member = "take", relative = "src/kvist/emit.odin", snippet = "emit_core_take_helper :: proc"},
    {import_path = "kvist:arr", member = "drop", relative = "src/kvist/emit.odin", snippet = "emit_core_drop_helper :: proc"},
    {import_path = "kvist:arr", member = "sort", relative = "src/kvist/emit.odin", snippet = "emit_core_sort_helper :: proc"},
    {import_path = "kvist:arr", member = "sort!", relative = "src/kvist/emit.odin", snippet = "emit_core_sort_in_place_helper :: proc"},
    {import_path = "kvist:str", member = "count", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/count\" || head.text == \"str/count\""},
    {import_path = "kvist:str", member = "get", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/get\" || head.text == \"str/get\" || head.text == \"map/get\""},
    {import_path = "kvist:str", member = "slice", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/slice\" || head.text == \"str/slice\""},
    {import_path = "kvist:str", member = "contains?", relative = "src/kvist/emit.odin", snippet = "if head.text == \"str/contains?\""},
    {import_path = "kvist:map", member = "empty", relative = "src/kvist/emit.odin", snippet = "if head.text == \"map/empty\""},
    {import_path = "kvist:map", member = "of", relative = "src/kvist/emit.odin", snippet = "if head.text == \"map/of\""},
    {import_path = "kvist:map", member = "get", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/get\" || head.text == \"str/get\" || head.text == \"map/get\""},
    {import_path = "kvist:map", member = "contains?", relative = "src/kvist/emit.odin", snippet = "if head.text == \"map/contains?\" || head.text == \"set/contains?\""},
    {import_path = "kvist:set", member = "empty", relative = "src/kvist/emit.odin", snippet = "if head.text == \"set/empty\""},
    {import_path = "kvist:set", member = "of", relative = "src/kvist/emit.odin", snippet = "if head.text == \"set/of\""},
    {import_path = "kvist:set", member = "contains?", relative = "src/kvist/emit.odin", snippet = "if head.text == \"map/contains?\" || head.text == \"set/contains?\""},
    {import_path = "kvist:set", member = "add!", relative = "src/kvist/emit.odin", snippet = "if head.text == \"set/add!\""},
    {import_path = "kvist:struct", member = "fields", relative = "src/kvist/emit.odin", snippet = "if head.text == \"struct/fields\" || head.text == \"struct/types\""},
    {import_path = "kvist:struct", member = "types", relative = "src/kvist/emit.odin", snippet = "if head.text == \"struct/fields\" || head.text == \"struct/types\""},
}

LANGUAGE_SOURCE_ENTRIES :: []Language_Source_Entry{
    {name = "package", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"package\":"},
    {name = "import", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"import\":"},
    {name = "const", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"const\":"},
    {name = "struct", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"struct\":"},
    {name = "enum", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"enum\":"},
    {name = "union", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"union\":"},
    {name = "proc", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "parse_proc_decl :: proc"},
    {name = "odin", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"odin\":"},
    {name = "let", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"let\":"},
    {name = "do", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"do\":"},
    {name = "if", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_if_like :: proc"},
    {name = "when", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"when\":"},
    {name = "cond", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_cond_stmt :: proc"},
    {name = "switch", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_switch_stmt :: proc"},
    {name = "set!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"set!\":"},
    {name = "return", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"return\":"},
    {name = "defer", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"defer\":"},
    {name = "for", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"for\":"},
    {name = "each", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"each\":"},
    {name = "update", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"update\":"},
    {name = "update!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"update!\":"},
    {name = "comment", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"comment\":"},
    {name = "new", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"new\""},
    {name = "make", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"make\""},
    {name = "get", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"get\""},
    {name = "nil?", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"nil?\""},
    {name = "type", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "if is_symbol(form.items[0], \"type\")"},
    {name = "in", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if op == \"in\" || op == \"not-in\""},
    {name = "not-in", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if op == \"in\" || op == \"not-in\""},
    {name = "break", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"break\":"},
    {name = "continue", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"continue\":"},
    {name = "with-allocator", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_with_allocator_stmt :: proc"},
    {name = "with-temp-allocator", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_with_temp_allocator_stmt :: proc"},
    {name = "with-delete", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_with_delete_stmt :: proc"},
    {name = "slurp", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"slurp\""},
    {name = "spit", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"spit\""},
    {name = "tap>", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"tap>\""},
    {name = "->", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_thread_expr :: proc"},
    {name = "->>", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_thread_expr :: proc"},
    {name = "map", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_map_helper :: proc"},
    {name = "filter", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_filter_helper :: proc"},
    {name = "remove", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_remove_helper :: proc"},
    {name = "reduce", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_reduce_helper :: proc"},
    {name = "map-indexed", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_map_indexed_helper :: proc"},
    {name = "keep", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_keep_helper :: proc"},
    {name = "mapcat", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_mapcat_helper :: proc"},
    {name = "concat", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_concat_helper :: proc"},
    {name = "merge", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_merge_helper :: proc"},
    {name = "merge!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_merge_in_place_helper :: proc"},
    {name = "into", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_into_helper :: proc"},
    {name = "into!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if head.text == \"into!\""},
    {name = "interpose", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_interpose_helper :: proc"},
    {name = "interleave", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_interleave_helper :: proc"},
    {name = "reverse", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_reverse_helper :: proc"},
    {name = "reverse!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_reverse_in_place_helper :: proc"},
    {name = "shuffle", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_shuffle_helper :: proc"},
    {name = "shuffle!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_shuffle_in_place_helper :: proc"},
    {name = "sort", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_sort_helper :: proc"},
    {name = "sort!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_sort_in_place_helper :: proc"},
    {name = "sort-by", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_sort_by_helper :: proc"},
    {name = "sort-by!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_sort_by_in_place_helper :: proc"},
    {name = "map!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_map_in_place_helper :: proc"},
    {name = "map-indexed!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_map_indexed_in_place_helper :: proc"},
    {name = "filter!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_filter_in_place_helper :: proc"},
    {name = "remove!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_remove_in_place_helper :: proc"},
    {name = "keep!", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_keep_in_place_helper :: proc"},
    {name = "split-at", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_split_at_helper :: proc"},
    {name = "partition", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_partition_helper :: proc"},
    {name = "partition-all", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_partition_all_helper :: proc"},
    {name = "partition-by", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_partition_by_helper :: proc"},
    {name = "zipmap", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_zipmap_helper :: proc"},
    {name = "index-by", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_index_by_helper :: proc"},
    {name = "group-by", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_group_by_helper :: proc"},
    {name = "frequencies", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_frequencies_helper :: proc"},
    {name = "keys", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_keys_helper :: proc"},
    {name = "vals", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_vals_helper :: proc"},
    {name = "distinct", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_distinct_helper :: proc"},
    {name = "distinct-by", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_distinct_by_helper :: proc"},
    {name = "range", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_range_helper :: proc"},
    {name = "repeat", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_repeat_helper :: proc"},
    {name = "repeatedly", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_repeatedly_helper :: proc"},
    {name = "iterate", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_iterate_helper :: proc"},
    {name = "cycle", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_cycle_helper :: proc"},
    {name = "take", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_take_helper :: proc"},
    {name = "drop", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_drop_helper :: proc"},
    {name = "butlast", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if head.text == \"first\" || head.text == \"second\""},
    {name = "drop-last", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_drop_last_helper :: proc"},
    {name = "take-nth", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_take_nth_helper :: proc"},
    {name = "take-while", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_take_while_helper :: proc"},
    {name = "drop-while", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_drop_while_helper :: proc"},
    {name = "find", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_find_helper :: proc"},
    {name = "some?", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_some_helper :: proc"},
    {name = "every?", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "emit_core_every_helper :: proc"},
    {name = "first", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if head.text == \"first\" || head.text == \"second\""},
    {name = "second", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if head.text == \"first\" || head.text == \"second\""},
    {name = "last", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if head.text == \"first\" || head.text == \"second\""},
    {name = "nth", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if head.text == \"nth\""},
    {name = "rest", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if head.text == \"first\" || head.text == \"second\""},
    {name = "empty?", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if head.text == \"first\" || head.text == \"second\""},
    {name = "count", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if head.text == \"first\" || head.text == \"second\""},
    {name = "contains?", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if op == \"in?\" || op == \"contains?\""},
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
    builtin_symbols_write_entry(builder, "kvist macro", "when-let", "(when-let [value bool expr] body...)", "Bind a value and explicit boolean result from a multi-return expression. Run the body only when the boolean is true. Expands to a destructuring let plus when.")
    builtin_symbols_write_entry(builder, "kvist macro", "if-let", "(if-let [value bool expr] then else)", "Bind a value and explicit boolean result from a multi-return expression. Evaluate the then branch when the boolean is true, otherwise the else branch. Expands to a destructuring let plus if.")
    builtin_symbols_write_entry(builder, "kvist macro", "when-ok", "(when-ok [value err expr] body...)", "Bind a value and Odin error result from a multi-return expression. Run the body only when the error equals Odin's zero value {}. Expands to a destructuring let plus when.")
    builtin_symbols_write_entry(builder, "kvist macro", "if-ok", "(if-ok [value err expr] then else)", "Bind a value and Odin error result from a multi-return expression. Evaluate the then branch when the error equals Odin's zero value {}, otherwise the else branch. Expands to a destructuring let plus if.")
    builtin_symbols_write_entry(builder, "kvist core", "println", "(println value...)", "Print one or more values. Kvist lowers this to fmt output and auto-imports core:fmt when needed.")
    builtin_symbols_write_entry(builder, "kvist core", "doc", "(doc 'symbol)", "Print the stored docstring for a declaration name.")
    builtin_symbols_write_entry(builder, "kvist form", "update!", "(update! target key-or-field value-or-updater ...)", "Mutate a struct field, array/slice slot, or map key in place. Supports replacement and updater forms such as inc or +.")
    builtin_symbols_write_entry(builder, "kvist form", "update", "(update target key-or-field value-or-updater ...)", "Return an updated copy. Currently supported for struct fields.")
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

import_entry_from_form :: proc(form: CST_Form) -> (Imported_Symbol_Entry, bool) {
    if form.kind != .List || len(form.items) == 0 || !is_symbol(form.items[0], "import") {
        return {}, false
    }
    if len(form.items) == 2 && form.items[1].kind == .String {
        path := import_path_text(form.items[1])
        alias := import_default_alias(path)
        if alias == "" {
            return {}, false
        }
        return Imported_Symbol_Entry{alias = alias, path = path}, true
    }
    if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
        path := import_path_text(form.items[2])
        return Imported_Symbol_Entry{alias = map_name(form.items[1].text), path = path}, true
    }
    return {}, false
}

odin_root_path :: proc() -> (string, bool) {
    state, stdout, stderr, err := os.process_exec(
        os.Process_Desc{command = {"odin", "root"}},
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    if err != nil || !state.exited || state.exit_code != 0 {
        return "", false
    }
    return strings.trim_space(string(stdout)), true
}

odin_import_dir :: proc(root, import_path: string) -> (string, bool) {
    switch {
    case strings.has_prefix(import_path, "core:"):
        path, err := os.join_path({root, "core", import_path[5:]}, context.allocator)
        if err != nil {
            return "", false
        }
        return path, true
    case strings.has_prefix(import_path, "vendor:"):
        path, err := os.join_path({root, "vendor", import_path[7:]}, context.allocator)
        if err != nil {
            return "", false
        }
        return path, true
    case:
        return "", false
    }
}

trim_line_ws :: proc(text: string) -> string {
    return strings.trim_space(text)
}

line_start_offset :: proc(source: string, line_start: int) -> int {
    if line_start <= 0 {
        return 0
    }
    line := 1
    for i := 0; i < len(source); i += 1 {
        if line == line_start {
            return i
        }
        if source[i] == '\n' {
            line += 1
        }
    }
    return len(source)
}

odin_line_range :: proc(source: string, line_start: int) -> (start, end: int) {
    start = line_start_offset(source, line_start)
    end = start
    for end < len(source) && source[end] != '\n' {
        end += 1
    }
    return
}

odin_signature_at_line :: proc(source: string, line_start: int) -> string {
    start, end := odin_line_range(source, line_start)
    if start >= len(source) {
        return ""
    }
    line := trim_line_ws(source[start:end])
    if strings.contains(line, ":: proc {") {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, line)
        current := line_start + 1
        for current <= 1000000 {
            next_start, next_end := odin_line_range(source, current)
            if next_start >= len(source) {
                break
            }
            next_line := trim_line_ws(source[next_start:next_end])
            strings.write_string(&builder, " ")
            strings.write_string(&builder, next_line)
            if next_line == "}" {
                break
            }
            current += 1
        }
        return strings.join(strings.fields(strings.to_string(builder))[:], " ", context.allocator)
    }
    compact := trim_line_ws(line)
    brace_idx := strings.index(compact, "{")
    if brace_idx >= 0 {
        compact = trim_line_ws(compact[:brace_idx])
    }
    return strings.join(strings.fields(compact)[:], " ", context.allocator)
}

odin_clean_doc_comment_line :: proc(line: string) -> string {
    text := strings.trim_left(line, " \t")
    if strings.has_prefix(text, "///") {
        return strings.trim_left(text[3:], " \t")
    }
    if strings.has_prefix(text, "//") {
        return strings.trim_left(text[2:], " \t")
    }
    return text
}

odin_clean_block_doc_line :: proc(line: string) -> string {
    text := strings.trim_space(line)
    if strings.has_prefix(text, "*") {
        return strings.trim_left(text[1:], " \t")
    }
    return text
}

odin_clean_block_doc_comment :: proc(text: string) -> string {
    value := text
    if strings.has_prefix(value, "/*") {
        value = value[2:]
    }
    if strings.has_suffix(value, "*/") {
        value = value[:len(value)-2]
    }
    lines := strings.split_lines(value, context.allocator)
    defer delete(lines)
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    seen_content := false
    pending_blank := false
    for line in lines {
        clean := odin_clean_block_doc_line(line)
        if clean == "" {
            if seen_content {
                pending_blank = true
            }
            continue
        }
        if pending_blank {
            strings.write_string(&builder, "\n")
        }
        if seen_content {
            strings.write_string(&builder, "\n")
        }
        strings.write_string(&builder, clean)
        seen_content = true
        pending_blank = false
    }
    return strings.to_string(builder)
}

odin_preceding_doc :: proc(source: string, line_start: int) -> string {
    lines := strings.split_lines(source, context.allocator)
    defer delete(lines)
    if line_start <= 1 || line_start > len(lines)+1 {
        return ""
    }
    docs: [dynamic]string
    defer delete(docs)
    idx := line_start - 2
doc_scan:
    for idx >= 0 {
        line := lines[idx]
        trimmed := strings.trim_space(line)
        switch {
        case strings.has_prefix(trimmed, "//"):
            append(&docs, odin_clean_doc_comment_line(line))
        case strings.has_suffix(trimmed, "*/"):
            builder := strings.builder_make()
            defer strings.builder_destroy(&builder)
            strings.write_string(&builder, line)
            idx -= 1
            for idx >= 0 {
                strings.write_string(&builder, "\n")
                strings.write_string(&builder, lines[idx])
                if strings.contains(lines[idx], "/*") {
                    break
                }
                idx -= 1
            }
            append(&docs, odin_clean_block_doc_comment(strings.to_string(builder)))
        case trimmed == "":
            break doc_scan
        case:
            break doc_scan
        }
        idx -= 1
    }
    if len(docs) == 0 {
        return ""
    }
    for i, j := 0, len(docs)-1; i < j; i, j = i+1, j-1 {
        docs[i], docs[j] = docs[j], docs[i]
    }
    return strings.join(docs[:], "\n", context.allocator)
}

odin_trim_doc :: proc(text: string) -> string {
    if text == "" {
        return ""
    }
    lines := strings.split_lines(text, context.allocator)
    defer delete(lines)
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    line_count := 0
    truncated := false
    for line in lines {
        clean := strings.trim_space(line)
        if clean == "" {
            break
        }
        if line_count >= 4 {
            truncated = true
            break
        }
        if line_count > 0 {
            strings.write_string(&builder, "\n")
        }
        strings.write_string(&builder, clean)
        line_count += 1
        if len(strings.to_string(builder)) >= 320 {
            truncated = true
            break
        }
    }
    out := strings.to_string(builder)
    if truncated && !strings.has_suffix(out, "...") {
        out = fmt.tprintf("%s...", out)
    }
    return out
}

odin_decl_rank :: proc(file, name: string) -> int {
    rank := 0
    if strings.contains(file, "/old/") {
        rank += 100
    }
    if strings.has_suffix(file, "_js.odin") {
        rank += 10
    }
    if strings.contains(file, "/example.odin") {
        rank += 200
    }
    if name == "main" {
        rank += 500
    }
    if strings.contains(name, "_") && len(name) > 0 && name[0] >= 'a' && name[0] <= 'z' {
        rank += 120
    }
    if strings.has_prefix(name, "fmt_") || strings.has_prefix(name, "int_from_") {
        rank += 120
    }
    return rank
}

odin_symbol_visible_to_tooling :: proc(file, name: string) -> bool {
    if name == "" || name == "main" {
        return false
    }
    if strings.contains(file, "/example.odin") || strings.contains(file, "/old/") {
        return false
    }
    if strings.has_suffix(file, "_js.odin") || strings.has_suffix(file, "_wasm.odin") {
        return false
    }
    if len(name) > 0 && name[0] == '_' {
        return false
    }
    if strings.contains(name, "_") && len(name) > 0 && name[0] >= 'a' && name[0] <= 'z' {
        return false
    }
    return true
}

imported_symbols_scan_odin_dir :: proc(builder: ^strings.Builder, alias, import_path, dir: string) {
    if !os.exists(dir) {
        return
    }
    entries, err := os.read_directory_by_path(dir, -1, context.allocator)
    if err != nil {
        return
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    best := make(map[string]string)
    defer delete(best)
    best_rank := make(map[string]int)
    defer delete(best_rank)

    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") {
            continue
        }
        path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil {
            continue
        }
        defer delete(path)
        data, read_err := os.read_entire_file_from_path(path, context.allocator)
        if read_err != nil {
            continue
        }
        source := string(data)
        defer delete(data)
        lines := strings.split_lines(source, context.allocator)
        defer delete(lines)
        for line, idx in lines {
            trimmed_left := strings.trim_left(line, " \t")
            name_end := strings.index(trimmed_left, "::")
            if name_end <= 0 {
                continue
            }
            name := strings.trim_space(trimmed_left[:name_end])
            if name == "" || name[0] == '_' || strings.contains(name, " ") || strings.contains(name, "\t") {
                continue
            }
            if !odin_symbol_visible_to_tooling(path, name) {
                continue
            }
            signature := odin_signature_at_line(source, idx+1)
            doc := odin_trim_doc(odin_preceding_doc(source, idx+1))
            rank := odin_decl_rank(path, name)
            key_slash := fmt.tprintf("%s/%s", alias, name)
            existing_rank, found_rank := best_rank[key_slash]
            if found_rank && existing_rank <= rank {
                delete(signature)
                delete(doc)
                continue
            }
            if prev, found := best[key_slash]; found {
                delete(prev)
            }
            if prev, found := best[fmt.tprintf("%s.%s", alias, name)]; found {
                delete(prev)
            }
            record_slash := strings.clone(fmt.tprintf("odin\t%s/%s\t%d\t1\t%s\t%s\t%s\t%s\n", alias, name, idx+1, import_path, signature, symbols_escape_doc_text(doc), path))
            record_dot := strings.clone(fmt.tprintf("odin\t%s.%s\t%d\t1\t%s\t%s\t%s\t%s\n", alias, name, idx+1, import_path, signature, symbols_escape_doc_text(doc), path))
            best[key_slash] = record_slash
            best[fmt.tprintf("%s.%s", alias, name)] = record_dot
            best_rank[key_slash] = rank
            best_rank[fmt.tprintf("%s.%s", alias, name)] = rank
        }
    }

    records: [dynamic]Imported_Symbol_Record
    defer delete(records)
    for name, record in best {
        rank := best_rank[name]
        append(&records, Imported_Symbol_Record{name = name, record = record, rank = rank})
    }
    sort.sort(sort.Interface{
        collection = rawptr(&records),
        len = proc(it: sort.Interface) -> int {
            items := (^([dynamic]Imported_Symbol_Record))(it.collection)
            return len(items^)
        },
        less = proc(it: sort.Interface, i, j: int) -> bool {
            items := (^([dynamic]Imported_Symbol_Record))(it.collection)
            if items[i].rank != items[j].rank {
                return items[i].rank < items[j].rank
            }
            return items[i].name < items[j].name
        },
        swap = proc(it: sort.Interface, i, j: int) {
            items := (^([dynamic]Imported_Symbol_Record))(it.collection)
            items[i], items[j] = items[j], items[i]
        },
    })
    for item in records {
        strings.write_string(builder, item.record)
    }
}

symbols_escape_doc_text :: proc(text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    lines := symbols_doc_lines_from_string(text)
    defer delete(lines)
    symbols_write_escaped_doc(&builder, lines[:])
    return strings.to_string(builder)
}

symbols_record_name :: proc(line: string) -> string {
    first_tab := strings.index(line, "\t")
    if first_tab < 0 {
        return ""
    }
    rest := line[first_tab+1:]
    second_tab := strings.index(rest, "\t")
    if second_tab < 0 {
        return ""
    }
    return rest[:second_tab]
}

symbols_append_unique_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, output: string) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        name := symbols_record_name(line)
        if name == "" {
            continue
        }
        if seen[name] {
            continue
        }
        seen[name] = true
        strings.write_string(builder, line)
        strings.write_byte(builder, '\n')
    }
}

repo_root_for_path :: proc(path: string) -> (string, bool) {
    current := path
    if current != "" && !os.is_absolute_path(current) {
        absolute, abs_err := os.get_absolute_path(current, context.allocator)
        if abs_err == nil {
            current = absolute
            defer delete(absolute)
        }
    }
    if !os.is_dir(current) {
        dir, _ := os.split_path(current)
        current = dir
    }
    for current != "" {
        marker, err := os.join_path({current, "cmd", "kvist", "main.odin"}, context.allocator)
        if err == nil {
            if os.exists(marker) {
                delete(marker)
                return current, true
            }
            delete(marker)
        }
        parent, _ := os.split_path(strings.trim_right(current, "/"))
        if parent == "" || parent == current {
            break
        }
        current = parent
    }
    return "", false
}

file_location_for_snippet :: proc(root, relative, snippet: string) -> (file: string, line, column: int, ok: bool) {
    path, join_err := os.join_path({root, relative}, context.allocator)
    if join_err != nil {
        return "", 0, 0, false
    }
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        delete(path)
        return "", 0, 0, false
    }
    source := string(data)
    idx := strings.index(source, snippet)
    if idx < 0 {
        delete(data)
        delete(path)
        return "", 0, 0, false
    }
    line, column, _, _ = source_position(source, idx)
    delete(data)
    return path, line, column, true
}

symbols_write_record_doc_file :: proc(builder: ^strings.Builder, kind, name: string, line, column: int, detail, signature: string, doc_lines: []string, file: string) {
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t%s\t", kind, name, line, column, detail, signature)
    symbols_write_escaped_doc(builder, doc_lines)
    fmt.sbprintf(builder, "\t%s\n", file)
}

editor_builtin_symbols_append :: proc(builder: ^strings.Builder, seen: ^map[string]bool, repo_root: string) {
    for entry in BUILTIN_SOURCE_ENTRIES {
        temp := strings.builder_make()
        defer strings.builder_destroy(&temp)
        file, line, column, ok := file_location_for_snippet(repo_root, entry.relative, entry.snippet)
        if !ok {
            continue
        }
        switch entry.name {
        case "when-let":
            symbols_write_record_doc_file(&temp, "kvist macro", entry.name, line, column, "", "(when-let [value bool expr] body...)", symbols_doc_lines_from_string("Bind a value and explicit boolean result from a multi-return expression. Run the body only when the boolean is true. Expands to a destructuring let plus when.")[:], file)
        case "if-let":
            symbols_write_record_doc_file(&temp, "kvist macro", entry.name, line, column, "", "(if-let [value bool expr] then else)", symbols_doc_lines_from_string("Bind a value and explicit boolean result from a multi-return expression. Evaluate the then branch when the boolean is true, otherwise the else branch. Expands to a destructuring let plus if.")[:], file)
        case "when-ok":
            symbols_write_record_doc_file(&temp, "kvist macro", entry.name, line, column, "", "(when-ok [value err expr] body...)", symbols_doc_lines_from_string("Bind a value and Odin error result from a multi-return expression. Run the body only when the error equals Odin's zero value {}. Expands to a destructuring let plus when.")[:], file)
        case "if-ok":
            symbols_write_record_doc_file(&temp, "kvist macro", entry.name, line, column, "", "(if-ok [value err expr] then else)", symbols_doc_lines_from_string("Bind a value and Odin error result from a multi-return expression. Evaluate the then branch when the error equals Odin's zero value {}, otherwise the else branch. Expands to a destructuring let plus if.")[:], file)
        case "println":
            symbols_write_record_doc_file(&temp, "kvist core", entry.name, line, column, "", "(println value...)", symbols_doc_lines_from_string("Print one or more values. Kvist lowers this to fmt output and auto-imports core:fmt when needed.")[:], file)
        case "doc":
            symbols_write_record_doc_file(&temp, "kvist core", entry.name, line, column, "", "(doc 'symbol)", symbols_doc_lines_from_string("Print the stored docstring for a declaration name.")[:], file)
        case "update!":
            symbols_write_record_doc_file(&temp, "kvist form", entry.name, line, column, "", "(update! target key-or-field value-or-updater ...)", symbols_doc_lines_from_string("Mutate a struct field, array/slice slot, or map key in place. Supports replacement and updater forms such as inc or +.")[:], file)
        case "update":
            symbols_write_record_doc_file(&temp, "kvist form", entry.name, line, column, "", "(update target key-or-field value-or-updater ...)", symbols_doc_lines_from_string("Return an updated copy. Currently supported for struct fields.")[:], file)
        case "type":
            symbols_write_record_doc_file(&temp, "kvist form", entry.name, line, column, "", "(type Head Arg...)", symbols_doc_lines_from_string("Instantiate an Odin polymorphic type constructor. For example, (type chan.Chan int) lowers to chan.Chan(int) in both type and value positions.")[:], file)
        case:
        }
        symbols_append_unique_records(builder, seen, strings.to_string(temp))
        delete(file)
    }
}

editor_package_symbols_append :: proc(builder: ^strings.Builder, seen: ^map[string]bool, repo_root, import_path, alias: string) {
    for entry in PACKAGE_SOURCE_ENTRIES {
        if entry.import_path != import_path {
            continue
        }
        file, line, column, ok := file_location_for_snippet(repo_root, entry.relative, entry.snippet)
        if !ok {
            continue
        }
        signature := ""
        doc := ""
        switch import_path {
        case "kvist:arr":
            switch entry.member {
            case "count": signature = "(arr/count xs)"; doc = "Count elements in an array, fixed array, or slice."
            case "empty": signature = "(arr/empty T [capacity])"; doc = "Construct an empty dynamic array, optionally with capacity."
            case "dynamic": signature = "(arr/dynamic T [v1 v2 ...])"; doc = "Construct a dynamic array from a vector literal."
            case "fixed": signature = "(arr/fixed T [v1 v2 ...])"; doc = "Construct a fixed array from a vector literal."
            case "get": signature = "(arr/get xs index)"; doc = "Index into an array-family value."
            case "slice": signature = "(arr/slice xs start [end])"; doc = "Take a slice view over an array-family value."
            case "push!": signature = "(arr/push! xs value...)"; doc = "Append one or more values to a dynamic array."
            case "map": signature = "(arr/map f xs)"; doc = "Map over an array-family input and return an owned dynamic array."
            case "filter": signature = "(arr/filter pred xs)"; doc = "Filter an array-family input and return an owned dynamic array."
            case "map!": signature = "(arr/map! f xs)"; doc = "Map in place over a dynamic array."
            case "filter!": signature = "(arr/filter! pred xs)"; doc = "Filter in place over a dynamic array."
            case "take": signature = "(arr/take n xs)"; doc = "Take a leading slice or owned result from an array-family input."
            case "drop": signature = "(arr/drop n xs)"; doc = "Drop a leading prefix from an array-family input."
            case "sort": signature = "(arr/sort xs)"; doc = "Return a sorted owned array."
            case "sort!": signature = "(arr/sort! xs)"; doc = "Sort a dynamic array in place."
            }
        case "kvist:str":
            switch entry.member {
            case "count": signature = "(str/count s)"; doc = "Count characters or bytes in a string."
            case "get": signature = "(str/get s index)"; doc = "Index into a string."
            case "slice": signature = "(str/slice s start [end])"; doc = "Take a string slice."
            case "contains?": signature = "(str/contains? s needle)"; doc = "Return true when the string contains the needle."
            }
        case "kvist:map":
            switch entry.member {
            case "empty": signature = "(map/empty K V [capacity])"; doc = "Construct an empty map, optionally with capacity."
            case "of": signature = "(map/of K V {k1 v1 ...})"; doc = "Construct a map from a brace literal."
            case "get": signature = "(map/get m key [default])"; doc = "Look up a key in a map, optionally with a default."
            case "contains?": signature = "(map/contains? m key)"; doc = "Return true when the map contains the key."
            }
        case "kvist:set":
            switch entry.member {
            case "empty": signature = "(set/empty T [capacity])"; doc = "Construct an empty set, optionally with capacity."
            case "of": signature = "(set/of T [v1 v2 ...])"; doc = "Construct a set from a vector literal."
            case "contains?": signature = "(set/contains? s value)"; doc = "Return true when the set contains the value."
            case "add!": signature = "(set/add! s value)"; doc = "Insert a value into a set."
            }
        case "kvist:struct":
            switch entry.member {
            case "fields": signature = "(struct/fields target)"; doc = "Return source-level field names for a struct type or value."
            case "types": signature = "(struct/types target)"; doc = "Return source-level field types for a struct type or value."
            }
        }
        doc_lines := symbols_doc_lines_from_string(doc)
        defer delete(doc_lines)
        temp := strings.builder_make()
        defer strings.builder_destroy(&temp)
        symbols_write_record_doc_file(&temp, "kvist package", fmt.tprintf("%s/%s", alias, entry.member), line, column, import_path, signature, doc_lines[:], file)
        symbols_write_record_doc_file(&temp, "kvist package", fmt.tprintf("%s.%s", alias, entry.member), line, column, import_path, signature, doc_lines[:], file)
        symbols_append_unique_records(builder, seen, strings.to_string(temp))
        delete(file)
    }
}

editor_language_symbols_append :: proc(builder: ^strings.Builder, seen: ^map[string]bool, repo_root: string) {
    for entry in LANGUAGE_SOURCE_ENTRIES {
        file, line, column, ok := file_location_for_snippet(repo_root, entry.relative, entry.snippet)
        if !ok {
            continue
        }
        temp := strings.builder_make()
        defer strings.builder_destroy(&temp)
        symbols_write_record_doc_file(&temp, entry.kind, entry.name, line, column, entry.relative, "", nil, file)
        symbols_append_unique_records(builder, seen, strings.to_string(temp))
        delete(file)
    }
}

imported_symbols_source :: proc(path, source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return "", clone_compile_error(err_forms, result_allocator), false
    }
    odin_root, have_odin_root := odin_root_path()
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")
    for top in forms {
        entry, ok_import := import_entry_from_form(top.form)
        if !ok_import {
            continue
        }
        if strings.has_prefix(entry.path, "kvist:") {
            _ = package_symbols_append(&builder, entry.path, entry.alias)
            continue
        }
        if !have_odin_root {
            continue
        }
        dir, ok_dir := odin_import_dir(odin_root, entry.path)
        if !ok_dir {
            continue
        }
        imported_symbols_scan_odin_dir(&builder, entry.alias, entry.path, dir)
        delete(dir)
    }
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}

editor_symbols_source :: proc(path, source: string) -> (output: string, err: Compile_Error, ok: bool) {
    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return "", clone_compile_error(err_forms, context.allocator), false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")

    seen := make(map[string]bool)
    defer delete(seen)
    repo_root, _ := repo_root_for_path(path)

    local_output, local_err, ok_local := symbols_source(source)
    if !ok_local {
        return "", local_err, false
    }
    symbols_append_unique_records(&builder, &seen, local_output)
    delete(local_output)

    for entry in KVIST_CANONICAL_IMPORTS_FOR_EDITOR {
        if repo_root != "" {
            editor_package_symbols_append(&builder, &seen, repo_root, entry.path, entry.alias)
        } else {
            package_output, ok_package := package_symbols_source(entry.path, entry.alias)
            if !ok_package {
                continue
            }
            symbols_append_unique_records(&builder, &seen, package_output)
            delete(package_output)
        }
    }

    for top in forms {
        entry, ok_import := import_entry_from_form(top.form)
        if !ok_import || !strings.has_prefix(entry.path, "kvist:") {
            continue
        }
        if repo_root != "" {
            editor_package_symbols_append(&builder, &seen, repo_root, entry.path, entry.alias)
        } else {
            package_output, ok_package := package_symbols_source(entry.path, entry.alias)
            if !ok_package {
                continue
            }
            symbols_append_unique_records(&builder, &seen, package_output)
            delete(package_output)
        }
    }

    imported_output, imported_err, ok_imported := imported_symbols_source(path, source)
    if !ok_imported {
        return "", imported_err, false
    }
    symbols_append_unique_records(&builder, &seen, imported_output)
    delete(imported_output)

    if repo_root != "" {
        editor_builtin_symbols_append(&builder, &seen, repo_root)
        editor_language_symbols_append(&builder, &seen, repo_root)
    } else {
        builtin_output := builtin_symbols_source()
        symbols_append_unique_records(&builder, &seen, builtin_output)
        delete(builtin_output)
    }

    return strings.clone(strings.to_string(builder)), {}, true
}

package_symbols_write_entry :: proc(builder: ^strings.Builder, alias, import_path, member, signature, doc: string) {
    doc_lines := symbols_doc_lines_from_string(doc)
    defer delete(doc_lines)
    symbols_write_record_doc(builder, "kvist package", fmt.tprintf("%s/%s", alias, member), "", Span{start = 0, end = 0, source = .File}, import_path, signature, doc_lines[:])
    symbols_write_record_doc(builder, "kvist package", fmt.tprintf("%s.%s", alias, member), "", Span{start = 0, end = 0, source = .File}, import_path, signature, doc_lines[:])
}

package_symbols_append :: proc(builder: ^strings.Builder, import_path, alias: string) -> bool {
    switch import_path {
    case "kvist:arr":
        package_symbols_write_entry(builder, alias, import_path, "count", "(arr/count xs)", "Count elements in an array, fixed array, or slice.")
        package_symbols_write_entry(builder, alias, import_path, "empty", "(arr/empty T [capacity])", "Construct an empty dynamic array, optionally with capacity.")
        package_symbols_write_entry(builder, alias, import_path, "dynamic", "(arr/dynamic T [v1 v2 ...])", "Construct a dynamic array from a vector literal.")
        package_symbols_write_entry(builder, alias, import_path, "fixed", "(arr/fixed T [v1 v2 ...])", "Construct a fixed array from a vector literal.")
        package_symbols_write_entry(builder, alias, import_path, "get", "(arr/get xs index)", "Index into an array-family value.")
        package_symbols_write_entry(builder, alias, import_path, "slice", "(arr/slice xs start [end])", "Take a slice view over an array-family value.")
        package_symbols_write_entry(builder, alias, import_path, "push!", "(arr/push! xs value...)", "Append one or more values to a dynamic array.")
        package_symbols_write_entry(builder, alias, import_path, "map", "(arr/map f xs)", "Map over an array-family input and return an owned dynamic array.")
        package_symbols_write_entry(builder, alias, import_path, "filter", "(arr/filter pred xs)", "Filter an array-family input and return an owned dynamic array.")
        package_symbols_write_entry(builder, alias, import_path, "map!", "(arr/map! f xs)", "Map in place over a dynamic array.")
        package_symbols_write_entry(builder, alias, import_path, "filter!", "(arr/filter! pred xs)", "Filter in place over a dynamic array.")
        package_symbols_write_entry(builder, alias, import_path, "take", "(arr/take n xs)", "Take a leading slice or owned result from an array-family input.")
        package_symbols_write_entry(builder, alias, import_path, "drop", "(arr/drop n xs)", "Drop a leading prefix from an array-family input.")
        package_symbols_write_entry(builder, alias, import_path, "sort", "(arr/sort xs)", "Return a sorted owned array.")
        package_symbols_write_entry(builder, alias, import_path, "sort!", "(arr/sort! xs)", "Sort a dynamic array in place.")
        return true
    case "kvist:str":
        package_symbols_write_entry(builder, alias, import_path, "count", "(str/count s)", "Count characters or bytes in a string.")
        package_symbols_write_entry(builder, alias, import_path, "get", "(str/get s index)", "Index into a string.")
        package_symbols_write_entry(builder, alias, import_path, "slice", "(str/slice s start [end])", "Take a string slice.")
        package_symbols_write_entry(builder, alias, import_path, "contains?", "(str/contains? s needle)", "Return true when the string contains the needle.")
        return true
    case "kvist:map":
        package_symbols_write_entry(builder, alias, import_path, "empty", "(map/empty K V [capacity])", "Construct an empty map, optionally with capacity.")
        package_symbols_write_entry(builder, alias, import_path, "of", "(map/of K V {k1 v1 ...})", "Construct a map from a brace literal.")
        package_symbols_write_entry(builder, alias, import_path, "get", "(map/get m key [default])", "Look up a key in a map, optionally with a default.")
        package_symbols_write_entry(builder, alias, import_path, "contains?", "(map/contains? m key)", "Return true when the map contains the key.")
        return true
    case "kvist:set":
        package_symbols_write_entry(builder, alias, import_path, "empty", "(set/empty T [capacity])", "Construct an empty set, optionally with capacity.")
        package_symbols_write_entry(builder, alias, import_path, "of", "(set/of T [v1 v2 ...])", "Construct a set from a vector literal.")
        package_symbols_write_entry(builder, alias, import_path, "contains?", "(set/contains? s value)", "Return true when the set contains the value.")
        package_symbols_write_entry(builder, alias, import_path, "add!", "(set/add! s value)", "Insert a value into a set.")
        return true
    case "kvist:struct":
        package_symbols_write_entry(builder, alias, import_path, "fields", "(struct/fields target)", "Return source-level field names for a struct type or value.")
        package_symbols_write_entry(builder, alias, import_path, "types", "(struct/types target)", "Return source-level field types for a struct type or value.")
        return true
    case:
        return false
    }
}

package_symbols_source :: proc(import_path, alias: string) -> (output: string, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    resolved_alias := alias
    if resolved_alias == "" {
        resolved_alias = import_default_alias(import_path)
    }
    if resolved_alias == "" {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")
    if !package_symbols_append(&builder, import_path, resolved_alias) {
        return "", false
    }
    return strings.clone(strings.to_string(builder), result_allocator), true
}

import_default_alias :: proc(path: string) -> string {
    end := len(path)
    for end > 0 && path[end-1] == '/' {
        end -= 1
    }
    start := end
    for start > 0 {
        ch := path[start-1]
        if ch == '/' || ch == ':' {
            break
        }
        start -= 1
    }
    if start >= end {
        return ""
    }
    return map_name(path[start:end])
}

symbols_write_record :: proc(builder: ^strings.Builder, kind, name: string, source: string, span: Span, detail: string = "") {
    line, column := 1, 1
    if source != "" {
        line, column, _, _ = source_position(source, span.start)
    }
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t\t\n", kind, name, line, column, detail)
}

symbols_clean_doc_line :: proc(line: string) -> string {
    text := line
    if len(text) >= 2 && text[0] == '/' && text[1] == '/' {
        text = text[2:]
    }
    if len(text) > 0 && text[0] == ' ' {
        text = text[1:]
    }
    return text
}

symbols_write_escaped_doc :: proc(builder: ^strings.Builder, doc_lines: []string) {
    for line, i in doc_lines {
        if i > 0 {
            strings.write_string(builder, "\\n")
        }
        text := symbols_clean_doc_line(line)
        for ch in text {
            switch ch {
            case '\\':
                strings.write_string(builder, "\\\\")
            case '\t':
                strings.write_string(builder, "\\t")
            case '\r':
                strings.write_string(builder, "\\r")
            case '\n':
                strings.write_string(builder, "\\n")
            case:
                strings.write_rune(builder, ch)
            }
        }
    }
}

symbols_write_record_doc :: proc(builder: ^strings.Builder, kind, name: string, source: string, span: Span, detail: string, signature: string, doc_lines: []string) {
    line, column := 1, 1
    if source != "" {
        line, column, _, _ = source_position(source, span.start)
    }
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t%s\t", kind, name, line, column, detail, signature)
    symbols_write_escaped_doc(builder, doc_lines)
    strings.write_byte(builder, '\n')
}

symbols_proc_signature :: proc(name: string, decl: Proc_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    fmt.sbprintf(&builder, "(%s [", name)
    for param, idx in decl.params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s: %s", param.name, param.ty)
    }
    strings.write_string(&builder, "]")

    #partial switch decl.returns.kind {
    case .Single:
        fmt.sbprintf(&builder, " -> %s", decl.returns.single_ty)
    case .Named:
        strings.write_string(&builder, " -> [")
        for field, idx in decl.returns.named {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            fmt.sbprintf(&builder, "%s: %s", field.name, field.ty)
        }
        strings.write_string(&builder, "]")
    case:
    }

    strings.write_string(&builder, ")")
    return strings.to_string(builder)
}

symbols_struct_signature :: proc(name: string, fields: []Struct_Field) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "(")
    strings.write_string(&builder, name)
    strings.write_string(&builder, " {")
    for field, idx in fields {
        if idx > 0 {
            strings.write_string(&builder, " ")
        }
        strings.write_string(&builder, ":")
        strings.write_string(&builder, field.source_name)
        strings.write_string(&builder, " ")
        strings.write_string(&builder, field.ty)
    }
    strings.write_string(&builder, "})")
    return strings.to_string(builder)
}

symbols_doc_lines_from_string :: proc(text: string) -> (lines: [dynamic]string) {
    start := 0
    for i := 0; i <= len(text); i += 1 {
        if i == len(text) || text[i] == '\n' {
            line := text[start:i]
            append(&lines, fmt.tprintf("// %s", line))
            start = i + 1
        }
    }
    if len(lines) == 0 {
        append(&lines, "// ")
    }
    return lines
}

symbols_append_doc_lines :: proc(base, extra: []string) -> (lines: [dynamic]string) {
    for line in base {
        append(&lines, line)
    }
    for line in extra {
        append(&lines, line)
    }
    return lines
}

symbols_write_fields :: proc(builder: ^strings.Builder, source, parent: string, fields: CST_Form) {
    if fields.kind != .Brace {
        return
    }
    i := 0
    for i < len(fields.items) {
        if i+1 >= len(fields.items) {
            return
        }
        key := fields.items[i]
        if key.kind == .Keyword && len(key.text) > 1 {
            name := fmt.tprintf("%s.%s", parent, key.text[1:])
            symbols_write_record(builder, "field", name, source, key.span, parent)
        }
        i += 2
    }
}

symbols_write_enum_variants :: proc(builder: ^strings.Builder, source, parent: string, variants: CST_Form) {
    #partial switch variants.kind {
    case .Vector:
        for item in variants.items {
            if item.kind == .Symbol {
                name := fmt.tprintf("%s.%s", parent, item.text)
                symbols_write_record(builder, "variant", name, source, item.span, parent)
            }
        }
    case .Brace:
        i := 0
        for i < len(variants.items) {
            if i+1 >= len(variants.items) {
                return
            }
            key := variants.items[i]
            if key.kind == .Keyword && len(key.text) > 1 {
                name := fmt.tprintf("%s.%s", parent, key.text[1:])
                symbols_write_record(builder, "variant", name, source, key.span, parent)
            }
            i += 2
        }
    case:
    }
}

symbols_write_union_variants :: proc(builder: ^strings.Builder, source, parent: string, variants: CST_Form) {
    if variants.kind != .Brace {
        return
    }
    i := 0
    for i < len(variants.items) {
        if i+1 >= len(variants.items) {
            return
        }
        key := variants.items[i]
        if key.kind == .Keyword && len(key.text) > 1 {
            name := fmt.tprintf("%s.%s", parent, key.text[1:])
            symbols_write_record(builder, "variant", name, source, key.span, parent)
        }
        i += 2
    }
}

symbols_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return "", clone_compile_error(err_forms, result_allocator), false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")

    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
            continue
        }
        head := form.items[0].text
        switch head {
        case "import":
            if len(form.items) == 2 && form.items[1].kind == .String {
                path := import_path_text(form.items[1])
                alias := import_default_alias(path)
                if alias != "" {
                    symbols_write_record_doc(&builder, "import", alias, source, form.items[1].span, path, "", top.doc_lines[:])
                }
            } else if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
                alias := form.items[1].text
                path := import_path_text(form.items[2])
                symbols_write_record_doc(&builder, "import", alias, source, form.items[1].span, path, "", top.doc_lines[:])
            }
        case "const", "defconst":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                symbols_write_record_doc(&builder, "const", form.items[1].text, source, form.items[1].span, "", "", doc_lines[:])
            }
        case "defvar":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                symbols_write_record_doc(&builder, "var", form.items[1].text, source, form.items[1].span, "", "", doc_lines[:])
            }
        case "struct":
            if len(form.items) == 3 && form.items[1].kind == .Symbol {
                name := form.items[1].text
                signature := ""
                fields, err_fields, ok_fields := parse_struct_fields(form.items[2])
                if ok_fields {
                    signature = symbols_struct_signature(name, fields[:])
                } else {
                    _ = err_fields
                }
                symbols_write_record_doc(&builder, "struct", name, source, form.items[1].span, "", signature, top.doc_lines[:])
                symbols_write_fields(&builder, source, name, form.items[2])
            }
        case "defstruct":
            if (len(form.items) == 3 || len(form.items) == 4) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                field_index := 2
                if len(form.items) == 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    field_index = 3
                }
                signature := ""
                fields_sig, err_fields, ok_fields_sig := parse_defstruct_fields(form.items[field_index])
                if ok_fields_sig {
                    signature = symbols_struct_signature(name, fields_sig[:])
                } else {
                    _ = err_fields
                }
                symbols_write_record_doc(&builder, "struct", name, source, form.items[1].span, "", signature, doc_lines[:])
                symbols_write_fields(&builder, source, name, form.items[field_index])
            }
        case "enum":
            if len(form.items) == 3 && form.items[1].kind == .Symbol {
                name := form.items[1].text
                symbols_write_record_doc(&builder, "enum", name, source, form.items[1].span, "", "", top.doc_lines[:])
                symbols_write_enum_variants(&builder, source, name, form.items[2])
            }
        case "union":
            if len(form.items) == 3 && form.items[1].kind == .Symbol {
                name := form.items[1].text
                symbols_write_record_doc(&builder, "union", name, source, form.items[1].span, "", "", top.doc_lines[:])
                symbols_write_union_variants(&builder, source, name, form.items[2])
            }
        case "proc", "defn":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                proc_form := form
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    items: [dynamic]CST_Form
                    append(&items, form.items[0], form.items[1])
                    for item in form.items[3:] {
                        append(&items, item)
                    }
                    proc_form = CST_Form{kind = .List, items = items, span = form.span}
                }
                signature := ""
                proc_decl, err_proc, ok_proc := parse_proc_decl(proc_form)
                if ok_proc {
                    signature = symbols_proc_signature(form.items[1].text, proc_decl)
                } else {
                    _ = err_proc
                }
                symbols_write_record_doc(&builder, "proc", form.items[1].text, source, form.items[1].span, "", signature, doc_lines[:])
            }
        case "defmacro":
            if len(form.items) >= 3 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                signature := fmt.tprintf("(%s ...)", form.items[1].text)
                if len(form.items) >= 3 && form.items[2].kind == .Vector {
                    signature = fmt.tprintf("(%s %s)", form.items[1].text, form.items[2].text)
                } else if len(form.items) >= 4 && form.items[3].kind == .Vector {
                    signature = fmt.tprintf("(%s %s)", form.items[1].text, form.items[3].text)
                }
                symbols_write_record_doc(&builder, "macro", form.items[1].text, source, form.items[1].span, "", signature, doc_lines[:])
            }
        case:
        }
    }

    context.allocator = result_allocator
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}
