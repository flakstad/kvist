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

KVIST_CANONICAL_IMPORTS_FOR_EDITOR :: [15]Imported_Symbol_Entry{
    {alias = "core", path = "kvist:core"},
    {alias = "arr", path = "kvist:arr"},
    {alias = "str", path = "kvist:str"},
    {alias = "map", path = "kvist:map"},
    {alias = "set", path = "kvist:set"},
    {alias = "p", path = "kvist:parallel"},
    {alias = "soa", path = "kvist:soa"},
    {alias = "io", path = "kvist:io"},
    {alias = "json", path = "kvist:json"},
    {alias = "cli", path = "kvist:cli"},
    {alias = "http", path = "kvist:http"},
    {alias = "httpc", path = "kvist:http/client"},
    {alias = "session", path = "kvist:http/session"},
    {alias = "sse", path = "kvist:http/sse"},
    {alias = "dstar", path = "kvist:http/datastar"},
}

BUILTIN_SOURCE_ENTRIES :: []Builtin_Source_Entry{
    {name = "type", relative = "src/kvist/parse.odin", snippet = "if is_symbol(form.items[0], \"type\")"},
}

LANGUAGE_SOURCE_ENTRIES :: []Language_Source_Entry{
    {name = "package", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"package\":"},
    {name = "import", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"import\":"},
    {name = "def", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"def\", \"def-\":"},
    {name = "defvar", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defvar\", \"defvar-\":"},
    {name = "defstruct", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defstruct\", \"defstruct-\":"},
    {name = "defenum", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defenum\", \"defenum-\":"},
    {name = "defunion", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defunion\", \"defunion-\":"},
    {name = "defn", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defn\", \"defn-\":"},
    {name = "defmacro", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defmacro\", \"defmacro-\":"},
    {name = "defsource", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defsource\", \"defsource-\":"},
    {name = "attr", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "(attr name ...)"},
    {name = "export", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"export\":"},
    {name = "exports", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"exports\":"},
    {name = "fn", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_proc_literal_expr :: proc"},
    {name = "odin", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"odin\":"},
    {name = "let", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"let\":"},
    {name = "block", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"do\", \"block\":"},
    {name = "do", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"do\":"},
    {name = "if", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_if_like :: proc"},
    {name = "when", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "(when test body...)"},
    {name = "cond", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "(cond test expr ... :else expr)"},
    {name = "case", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "(case value clause ... :else expr)"},
    {name = "switch", kind = "compatibility syntax", relative = "src/kvist/emit.odin", snippet = "`switch` is compatibility syntax; use `case` or `cond`"},
    {name = "set!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"set!\":"},
    {name = "mut!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"mut!\":"},
    {name = "update!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "(update! place f args...)"},
    {name = "delete!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "(delete! target key)"},
    {name = "inc!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"inc!\", \"dec!\", \"toggle!\", \"negate!\":"},
    {name = "dec!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"inc!\", \"dec!\", \"toggle!\", \"negate!\":"},
    {name = "toggle!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"inc!\", \"dec!\", \"toggle!\", \"negate!\":"},
    {name = "negate!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"inc!\", \"dec!\", \"toggle!\", \"negate!\":"},
    {name = "return", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"return\":"},
    {name = "discard", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "(discard expr...)"},
    {name = "defer", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"defer\":"},
    {name = "for", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"for\":"},
    {name = "each", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"each\":"},
    {name = "make", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"make\""},
    {name = "get", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "(get target key)"},
    {name = "slice", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "(slice target start end)"},
    {name = "type", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "if is_symbol(form.items[0], \"type\")"},
    {name = "deref", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"^\" || head.text == \"deref\""},
    {name = "addr", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"&\" || head.text == \"addr\""},
    {name = "break", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"break\":"},
    {name = "continue", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"continue\":"},
    {name = "while", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"while\":"},
    {name = "with-allocator", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_with_allocator_stmt :: proc"},
    {name = "with-temp-allocator", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_with_temp_allocator_stmt :: proc"},
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
            key := fmt.tprintf("%s.%s", alias, name)
            existing_rank, found_rank := best_rank[key]
            if found_rank && existing_rank <= rank {
                delete(signature)
                delete(doc)
                continue
            }
            if prev, found := best[key]; found {
                delete(prev)
            }
            record := strings.clone(fmt.tprintf("odin\t%s.%s\t%d\t1\t%s\t%s\t%s\t%s\n", alias, name, idx+1, import_path, signature, symbols_escape_doc_text(doc), path))
            best[key] = record
            best_rank[key] = rank
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

symbols_record_key :: proc(line: string) -> string {
    fields, ok := symbols_split_record_fields(line)
    if !ok || len(fields) < 2 {
        return ""
    }
    return fmt.tprintf("%s\t%s", fields[0], fields[1])
}

symbols_record_detail :: proc(line: string) -> string {
    first_tab := strings.index(line, "\t")
    if first_tab < 0 {
        return ""
    }
    rest := line[first_tab+1:]
    for _ in 0..<3 {
        tab := strings.index(rest, "\t")
        if tab < 0 {
            return ""
        }
        rest = rest[tab+1:]
    }
    tab := strings.index(rest, "\t")
    if tab < 0 {
        return rest
    }
    return rest[:tab]
}

symbols_append_unique_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, output: string) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        key := symbols_record_key(line)
        if key == "" {
            continue
        }
        if seen[key] {
            continue
        }
        seen[key] = true
        strings.write_string(builder, line)
        strings.write_byte(builder, '\n')
    }
}

symbols_append_core_helper_alias_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, output: string) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        fields, ok_fields := symbols_split_record_fields(line)
        _ = ok_fields
        if len(fields) < 7 {
            delete(fields)
            continue
        }
        for len(fields) < 8 {
            append(&fields, "")
        }
        name := fields[1]
        if !strings.has_prefix(name, "core.") || len(name) <= len("core.") {
            delete(fields)
            continue
        }
        bare_name := name[len("core."):]
        if bare_name == "switch" {
            delete(fields)
            continue
        }
        key := fmt.tprintf("kvist helper\t%s", bare_name)
        if seen[key] {
            delete(key)
            delete(fields)
            continue
        }
        seen[key] = true
        fmt.sbprintf(builder, "kvist helper\t%s\t%s\t%s\tkvist:core\t%s\t%s\t%s\n", bare_name, fields[2], fields[3], fields[5], fields[6], fields[7])
        delete(fields)
    }
}

symbols_split_record_fields :: proc(line: string) -> (fields: [dynamic]string, ok: bool) {
    rest := line
    for {
        tab := strings.index(rest, "\t")
        if tab < 0 {
            append(&fields, rest)
            break
        }
        append(&fields, rest[:tab])
        rest = rest[tab+1:]
    }
    return fields, len(fields) >= 7
}

symbols_top_level_kind_exported :: proc(kind: string) -> bool {
    switch kind {
    case "const", "var", "struct", "enum", "union", "proc", "macro", "source":
        return true
    case:
        return false
    }
}

symbols_append_source_package_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, import_path, alias, package_file, output: string, package_kind: string = "") {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        fields, ok_fields := symbols_split_record_fields(line)
        _ = ok_fields
        if len(fields) < 4 {
            delete(fields)
            continue
        }
        for len(fields) < 7 {
            append(&fields, "")
        }
        kind := fields[0]
        name := fields[1]
        if !symbols_top_level_kind_exported(kind) {
            delete(fields)
            continue
        }
        if symbols_record_detail(line) == "private" {
            delete(fields)
            continue
        }
        line_text := fields[2]
        column_text := fields[3]
        signature := fields[5]
        doc := fields[6]
        kind_text := kind
        if package_kind != "" {
            kind_text = package_kind
        }
        dot_name := fmt.tprintf("%s.%s", alias, name)
        if !seen[dot_name] {
            seen[dot_name] = true
            fmt.sbprintf(builder, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", kind_text, dot_name, line_text, column_text, import_path, signature, doc, package_file)
        }
        delete(fields)
    }
}

symbols_append_html_syntax_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, import_path, alias, package_file: string, package_kind: string = "") {
    if import_path != "kvist:html" || alias == "" {
        return
    }
    kind_text := "macro"
    if package_kind != "" {
        kind_text = package_kind
    }
    signature := "(for [x xs] child...)"
    doc := "Repeat child markup inside html/render."
    slash_name := fmt.tprintf("%s/for", alias)
    if !seen[slash_name] {
        seen[slash_name] = true
        fmt.sbprintf(builder, "%s\t%s\t1\t1\t%s\t%s\t%s\t%s\n", kind_text, slash_name, import_path, signature, doc, package_file)
    }
    dot_name := fmt.tprintf("%s.for", alias)
    if !seen[dot_name] {
        seen[dot_name] = true
        fmt.sbprintf(builder, "%s\t%s\t1\t1\t%s\t%s\t%s\t%s\n", kind_text, dot_name, import_path, signature, doc, package_file)
    }
}

source_package_anchor_file :: proc(files: []Package_File) -> string {
    for file in files {
        _, name := os.split_path(file.path)
        dir, _ := os.split_path(file.path)
        if is_package_anchor_filename(dir, name) {
            return file.path
        }
    }
    if len(files) > 0 {
        return files[0].path
    }
    return ""
}

symbols_append_source_package_import_record :: proc(builder: ^strings.Builder, seen: ^map[string]bool, alias, import_path, file_path: string) {
    if alias == "" || file_path == "" {
        return
    }
    key := fmt.tprintf("source import\t%s", alias)
    if seen[key] {
        return
    }
    seen[key] = true
    temp := strings.builder_make()
    defer strings.builder_destroy(&temp)
    doc_lines := symbols_doc_lines_from_string(fmt.tprintf("Source package import %s.", import_path))
    defer delete(doc_lines)
    symbols_write_record_doc_file(&temp, "source import", alias, 1, 1, import_path, fmt.tprintf("(import %s \"%s\")", alias, import_path), doc_lines[:], file_path)
    strings.write_string(builder, strings.to_string(temp))
    strings.write_byte(builder, '\n')
}

symbols_append_local_package_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, file_path, output: string) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        fields, ok_fields := symbols_split_record_fields(line)
        _ = ok_fields
        if len(fields) < 4 {
            delete(fields)
            continue
        }
        for len(fields) < 7 {
            append(&fields, "")
        }
        kind := fields[0]
        name := fields[1]
        line_text := fields[2]
        column_text := fields[3]
        detail := fields[4]
        signature := fields[5]
        doc := fields[6]
        key := fmt.tprintf("%s\t%s", kind, name)
        if seen[key] {
            delete(fields)
            continue
        }
        seen[key] = true
        fmt.sbprintf(builder, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", kind, name, line_text, column_text, detail, signature, doc, file_path)
        delete(fields)
    }
}

editor_root_package_files :: proc(path, source: string) -> ([]Package_File, bool) {
    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        _ = err_forms
        return nil, false
    }
    package_name := ""
    for top in forms {
        if decl_head_name(top.form) == "package" && len(top.form.items) == 2 && top.form.items[1].kind == .Symbol {
            package_name = top.form.items[1].text
            break
        }
    }
    if package_name == "" {
        delete_borrowed_cst_top_form_slice(&forms)
        return nil, false
    }

    dir, file_name := os.split_path(path)
    if dir == "" {
        delete_borrowed_cst_top_form_slice(&forms)
        return nil, false
    }

    entries, dir_err := os.read_directory_by_path(dir, -1, context.allocator)
    if dir_err != nil {
        delete_borrowed_cst_top_form_slice(&forms)
        return nil, false
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    has_anchor := false
    matched: [dynamic]Package_File
    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".kvist") {
            continue
        }
        file_path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil {
            return nil, false
        }
        if entry.name == file_name {
            if is_package_anchor_filename(dir, entry.name) {
                has_anchor = true
            }
            append(&matched, Package_File{path = file_path, path_owned = true, source = source, package_name = package_name, forms = forms})
            continue
        }
        data, read_err := os.read_entire_file_from_path(file_path, context.allocator)
        if read_err != nil {
            continue
        }
        file_source := string(data)
        file_forms, _, ok_file_forms := read_top_forms(file_source)
        if !ok_file_forms {
            delete(data)
            continue
        }
        file_package_name := ""
        for top in file_forms {
            if decl_head_name(top.form) == "package" && len(top.form.items) == 2 && top.form.items[1].kind == .Symbol {
                file_package_name = top.form.items[1].text
                break
            }
        }
        if file_package_name != package_name {
            delete_borrowed_cst_top_form_slice(&file_forms)
            delete(data)
            continue
        }
        if is_package_anchor_filename(dir, entry.name) {
            has_anchor = true
        }
        append(&matched, Package_File{path = file_path, path_owned = true, source = file_source, package_name = file_package_name, forms = file_forms})
    }

    if len(matched) == 0 {
        delete_borrowed_cst_top_form_slice(&forms)
        return nil, false
    }
    if !has_anchor {
        files: [dynamic]Package_File
        append(&files, Package_File{path = path, source = source, package_name = package_name, forms = forms})
        return files[:], true
    }
    return matched[:], true
}

source_package_symbols_source :: proc(importer_path, import_path: string) -> (package_file, output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    resolved, err_resolve, ok_resolve := resolve_source_import_path(importer_path, import_path)
    if !ok_resolve {
        return "", "", clone_compile_error(err_resolve, result_allocator), false
    }
    defer delete(resolved)
    files, err_files, ok_files := read_package_files(resolved)
    if !ok_files {
        return "", "", clone_compile_error(err_files, result_allocator), false
    }
    defer package_file_slice_delete(files)
    _, err_package, ok_package := validate_package_files(resolved, files[:])
    if !ok_package {
        return "", "", clone_compile_error(err_package, result_allocator), false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")
    seen := make(map[string]bool)
    defer delete(seen)
    for file in files {
        context.allocator = result_allocator
        package_output, package_err, ok_package_output := symbols_source(file.source)
        context.allocator = context.temp_allocator
        if !ok_package_output {
            return "", "", clone_compile_error(package_err, result_allocator), false
        }
        symbols_append_source_package_records(&builder, &seen, import_path, import_default_alias(import_path), file.path, package_output)
        context.allocator = result_allocator
        delete(package_output)
        context.allocator = context.temp_allocator
    }
    symbols_append_html_syntax_records(&builder, &seen, import_path, import_default_alias(import_path), source_package_anchor_file(files[:]))
    resolved_copy, _ := strings.clone(resolved, result_allocator)
    output_copy, _ := strings.clone(strings.to_string(builder), result_allocator)
    return resolved_copy, output_copy, Compile_Error{}, true
}

repo_root_for_path :: proc(path: string) -> (string, bool) {
    current := path
    owned_current := ""
    if current != "" && !os.is_absolute_path(current) {
        absolute, abs_err := os.get_absolute_path(current, context.allocator)
        if abs_err == nil {
            current = absolute
            owned_current = absolute
        }
    }
    current_end := len(current)
    for current_end > 1 && current[current_end-1] == '/' {
        current_end -= 1
    }
    current = current[:current_end]
    if current != "" && !os.is_dir(current) {
        last_slash := -1
        for i := len(current) - 1; i >= 0; i -= 1 {
            if current[i] == '/' {
                last_slash = i
                break
            }
        }
        if last_slash < 0 {
            current = ""
        } else if last_slash == 0 {
            current = current[:1]
        } else {
            current = current[:last_slash]
        }
    }
    for current != "" {
        marker, err := os.join_path({current, "cmd", "kvist", "main.odin"}, context.allocator)
        if err == nil {
            if os.exists(marker) {
                delete(marker)
                root := strings.clone(current)
                if owned_current != "" {
                    delete(owned_current)
                }
                return root, true
            }
            delete(marker)
        }
        trimmed_end := len(current)
        for trimmed_end > 1 && current[trimmed_end-1] == '/' {
            trimmed_end -= 1
        }
        trimmed := current[:trimmed_end]
        last_slash := -1
        for i := len(trimmed) - 1; i >= 0; i -= 1 {
            if trimmed[i] == '/' {
                last_slash = i
                break
            }
        }
        parent := ""
        if last_slash == 0 {
            parent = trimmed[:1]
        } else if last_slash > 0 {
            parent = trimmed[:last_slash]
        }
        if parent == "" || parent == current {
            break
        }
        current = parent
    }
    if owned_current != "" {
        delete(owned_current)
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
        case "type":
            symbols_write_record_doc_file(&temp, "kvist form", entry.name, line, column, "", "(type Head Arg...)", symbols_doc_lines_from_string("Instantiate an Odin polymorphic type constructor. For example, (type chan.Chan int) lowers to chan.Chan(int) in both type and value positions.")[:], file)
        case:
        }
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
    defer delete_borrowed_cst_top_form_slice(&forms)
    odin_root, have_odin_root := odin_root_path()
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")
    seen := make(map[string]bool)
    defer delete(seen)
    for top in forms {
        entry, ok_import := import_entry_from_form(top.form)
        if !ok_import {
            continue
        }
        _, import_path, ok_source_import := source_import_alias_and_path(top.form, path)
        if ok_source_import {
            resolved, err_resolve, ok_resolve := resolve_source_import_path(path, import_path)
            if !ok_resolve {
                return "", clone_compile_error(err_resolve, result_allocator), false
            }
            files, err_files, ok_files := read_package_files(resolved)
            if !ok_files {
                delete(resolved)
                return "", clone_compile_error(err_files, result_allocator), false
            }
            defer package_file_slice_delete(files)
            _, err_package, ok_package := validate_package_files(resolved, files[:])
            if !ok_package {
                delete(resolved)
                return "", clone_compile_error(err_package, result_allocator), false
            }
            anchor := source_package_anchor_file(files[:])
            symbols_append_source_package_import_record(&builder, &seen, entry.alias, import_path, anchor)
            for file in files {
                context.allocator = result_allocator
                package_output, package_err, ok_package_output := symbols_source(file.source)
                context.allocator = context.temp_allocator
                if !ok_package_output {
                    delete(resolved)
                    return "", clone_compile_error(package_err, result_allocator), false
                }
                symbols_append_source_package_records(&builder, &seen, import_path, entry.alias, file.path, package_output)
                context.allocator = result_allocator
                delete(package_output)
                context.allocator = context.temp_allocator
            }
            symbols_append_html_syntax_records(&builder, &seen, import_path, entry.alias, anchor)
            delete(resolved)
            continue
        }
        if strings.has_prefix(entry.path, "kvist:") {
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
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")

    seen := make(map[string]bool)
    defer delete(seen)
    repo_root, _ := repo_root_for_path(path)
    if !os.exists(path) {
        cwd_repo_root, ok_cwd_repo_root := repo_root_for_path(".")
        if ok_cwd_repo_root {
            repo_root = cwd_repo_root
        }
    }

    package_files, ok_package_files := editor_root_package_files(path, source)
    files_for_imports: [dynamic]Package_File
    defer delete(files_for_imports)
    if ok_package_files {
        for file in package_files {
            context.allocator = result_allocator
            local_output, local_err, ok_local := symbols_source(file.source)
            context.allocator = context.temp_allocator
            if !ok_local {
                return "", local_err, false
            }
            symbols_append_local_package_records(&builder, &seen, file.path, local_output)
            symbols_append_local_field_records(&builder, &seen, file.path, file.source, file.forms[:])
            context.allocator = result_allocator
            delete(local_output)
            context.allocator = context.temp_allocator
            append(&files_for_imports, file)
        }
    } else {
        forms, err_forms, ok_forms := read_top_forms(source)
        if !ok_forms {
            return "", clone_compile_error(err_forms, result_allocator), false
        }
        defer delete_borrowed_cst_top_form_slice(&forms)
        context.allocator = result_allocator
        local_output, local_err, ok_local := symbols_source(source)
        context.allocator = context.temp_allocator
        if !ok_local {
            return "", local_err, false
        }
        symbols_append_local_package_records(&builder, &seen, path, local_output)
        symbols_append_local_field_records(&builder, &seen, path, source, forms[:])
        context.allocator = result_allocator
        delete(local_output)
        context.allocator = context.temp_allocator
        append(&files_for_imports, Package_File{path = path, source = source, forms = forms})
    }

    for entry in KVIST_CANONICAL_IMPORTS_FOR_EDITOR {
        context.allocator = result_allocator
        package_output, ok_package := package_symbols_source(entry.path, entry.alias, "kvist package")
        context.allocator = context.temp_allocator
        if !ok_package {
            continue
        }
        symbols_append_unique_records(&builder, &seen, package_output)
        if entry.path == "kvist:core" {
            symbols_append_core_helper_alias_records(&builder, &seen, package_output)
        }
        context.allocator = result_allocator
        delete(package_output)
        context.allocator = context.temp_allocator
    }

    for import_file in files_for_imports {
        for top in import_file.forms {
            alias, import_path, ok_source_import := source_import_alias_and_path(top.form, import_file.path)
            if ok_source_import {
                resolved, err_resolve, ok_resolve := resolve_source_import_path(import_file.path, import_path)
                if !ok_resolve {
                    return "", err_resolve, false
                }
                files, err_files, ok_files := read_package_files(resolved)
                if !ok_files {
                    delete(resolved)
                    return "", err_files, false
                }
                defer package_file_slice_delete(files)
                _, err_package, ok_package := validate_package_files(resolved, files[:])
                if !ok_package {
                    delete(resolved)
                    return "", err_package, false
                }
                anchor := source_package_anchor_file(files[:])
                symbols_append_source_package_import_record(&builder, &seen, alias, import_path, anchor)
                for file in files {
                    context.allocator = result_allocator
                    package_output, package_err, ok_package_output := symbols_source(file.source)
                    context.allocator = context.temp_allocator
                    if !ok_package_output {
                        delete(resolved)
                        return "", package_err, false
                    }
                    symbols_append_source_package_records(&builder, &seen, import_path, alias, file.path, package_output, "kvist package")
                    context.allocator = result_allocator
                    delete(package_output)
                    context.allocator = context.temp_allocator
                }
                delete(resolved)
                continue
            }

            entry, ok_import := import_entry_from_form(top.form)
            if !ok_import || !strings.has_prefix(entry.path, "kvist:") {
                continue
            }
            context.allocator = result_allocator
            package_output, ok_package := package_symbols_source(entry.path, entry.alias, "kvist package")
            context.allocator = context.temp_allocator
            if ok_package {
                symbols_append_unique_records(&builder, &seen, package_output)
                if entry.path == "kvist:core" {
                    symbols_append_core_helper_alias_records(&builder, &seen, package_output)
                }
                context.allocator = result_allocator
                delete(package_output)
                context.allocator = context.temp_allocator
            }
        }
    }

    for import_file in files_for_imports {
        context.allocator = result_allocator
        imported_output, imported_err, ok_imported := imported_symbols_source(import_file.path, import_file.source)
        context.allocator = context.temp_allocator
        if !ok_imported {
            return "", imported_err, false
        }
        symbols_append_unique_records(&builder, &seen, imported_output)
        context.allocator = result_allocator
        delete(imported_output)
        context.allocator = context.temp_allocator
    }

    if repo_root != "" {
        editor_builtin_symbols_append(&builder, &seen, repo_root)
        editor_language_symbols_append(&builder, &seen, repo_root)
    }
    context.allocator = result_allocator
    builtin_output := builtin_symbols_source()
    context.allocator = context.temp_allocator
    symbols_append_unique_records(&builder, &seen, builtin_output)
    context.allocator = result_allocator
    delete(builtin_output)
    context.allocator = context.temp_allocator
    context.allocator = result_allocator
    language_output := language_symbols_source()
    context.allocator = context.temp_allocator
    symbols_append_unique_records(&builder, &seen, language_output)
    context.allocator = result_allocator
    delete(language_output)
    context.allocator = context.temp_allocator
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}

package_symbols_source :: proc(import_path, alias: string, package_kind: string = "") -> (output: string, ok: bool) {
    result_allocator := context.allocator

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
    resolved, err_resolve, ok_resolve := resolve_source_import_path(".", import_path)
    if !ok_resolve {
        _ = err_resolve
        return "", false
    }
    defer delete(resolved)
    files, err_files, ok_files := read_package_files(resolved)
    if !ok_files {
        _ = err_files
        return "", false
    }
    defer package_file_slice_delete(files)
    _, err_package, ok_package := validate_package_files(resolved, files[:])
    if !ok_package {
        _ = err_package
        return "", false
    }
    seen := make(map[string]bool)
    defer delete(seen)
    for file in files {
        package_output, package_err, ok_package_output := symbols_source(file.source)
        if !ok_package_output {
            _ = package_err
            return "", false
        }
        symbols_append_source_package_records(&builder, &seen, import_path, resolved_alias, file.path, package_output, package_kind)
        delete(package_output)
    }
    symbols_append_html_syntax_records(&builder, &seen, import_path, resolved_alias, source_package_anchor_file(files[:]), package_kind)
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
        if param.has_default {
            strings.write_string(&builder, " = ")
            strings.write_string(&builder, symbols_form_text(param.default_value))
        }
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

symbols_source_signature :: proc(name: string, decl: Source_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    fmt.sbprintf(&builder, "(%s [", name)
    for param, idx in decl.params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s: %s", param.name, param.ty)
    }
    fmt.sbprintf(&builder, "] -> %s)", decl.item_ty)
    return strings.to_string(builder)
}

write_symbols_form :: proc(builder: ^strings.Builder, form: CST_Form) {
    #partial switch form.kind {
    case .List:
        strings.write_byte(builder, '(')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_symbols_form(builder, item)
        }
        strings.write_byte(builder, ')')
    case .Vector:
        strings.write_byte(builder, '[')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_symbols_form(builder, item)
        }
        strings.write_byte(builder, ']')
    case .Brace:
        strings.write_byte(builder, '{')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_symbols_form(builder, item)
        }
        strings.write_byte(builder, '}')
    case .Set:
        strings.write_string(builder, "#{")
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_symbols_form(builder, item)
        }
        strings.write_byte(builder, '}')
    case .Symbol, .Keyword, .String, .Number, .Bool, .Nil:
        strings.write_string(builder, form.text)
    }
}

symbols_form_text :: proc(form: CST_Form) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    write_symbols_form(&builder, form)
    return strings.clone(strings.to_string(builder))
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
        strings.write_string(&builder, field.source_name)
        strings.write_string(&builder, ":")
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
        } else if key.kind == .Symbol && len(key.text) > 1 && key.text[len(key.text)-1] == ':' {
            name := fmt.tprintf("%s.%s", parent, key.text[:len(key.text)-1])
            symbols_write_record(builder, "field", name, source, key.span, parent)
        }
        i += 2
    }
}

symbols_defstruct_field_index :: proc(form: CST_Form) -> (int, bool) {
    if form.kind != .List || len(form.items) < 3 || form.items[0].kind != .Symbol {
        return -1, false
    }
    head := form.items[0].text
    if head != "defstruct" && head != "defstruct-" && head != "defstate" {
        return -1, false
    }
    if form.items[1].kind != .Symbol {
        return -1, false
    }
    field_index := 2
    if len(form.items) >= 4 && form.items[2].kind == .String {
        field_index = 3
    }
    if field_index >= len(form.items) || form.items[field_index].kind != .Brace {
        return -1, false
    }
    return field_index, true
}

symbols_struct_fields_for_type :: proc(forms: []CST_Top_Form, ty: string) -> (fields: [dynamic]Struct_Field, ok: bool) {
    normalized_ty := ty
    if strings.has_prefix(normalized_ty, "^") {
        normalized_ty = normalized_ty[1:]
    }
    for top in forms {
        form := top.form
        field_index, ok_fields_index := symbols_defstruct_field_index(form)
        if !ok_fields_index {
            continue
        }
        source_name := form.items[1].text
        mapped_name := map_name(source_name)
        if normalized_ty != source_name && normalized_ty != mapped_name {
            delete(mapped_name)
            continue
        }
        delete(mapped_name)
        parsed, err_fields, ok_fields := parse_defstruct_fields(form.items[field_index])
        if ok_fields {
            return parsed, true
        }
        _ = err_fields
    }
    return fields, false
}

symbols_local_type_lookup :: proc(bindings: []Local_Type_Binding, name: string) -> (string, bool) {
    for idx := len(bindings)-1; idx >= 0; idx -= 1 {
        if bindings[idx].name == name {
            return bindings[idx].ty, true
        }
    }
    return "", false
}

symbols_local_type_bind :: proc(bindings: ^[dynamic]Local_Type_Binding, name, ty: string) {
    if name == "" || ty == "" {
        return
    }
    append(bindings, Local_Type_Binding{name = name, ty = ty})
}

symbols_obvious_local_value_type :: proc(form: CST_Form, bindings: []Local_Type_Binding) -> (string, bool) {
    if form.kind == .Symbol {
        ty, ok := symbols_local_type_lookup(bindings, form.text)
        if ok {
            return ty, true
        }
        mapped_name := map_name(form.text)
        defer delete(mapped_name)
        return symbols_local_type_lookup(bindings, mapped_name)
    }
    if form.kind == .List && len(form.items) == 2 && form.items[0].kind == .Symbol {
        arg := form.items[1]
        if arg.kind == .Brace || arg.kind == .Vector {
            return map_name(form.items[0].text), true
        }
    }
    return "", false
}

symbols_write_editor_record :: proc(
    builder: ^strings.Builder,
    seen: ^map[string]bool,
    kind, name: string,
    source: string,
    span: Span,
    detail: string,
    file_path: string,
) {
    key := fmt.tprintf("%s\t%s", kind, name)
    if seen[key] {
        return
    }
    seen[key] = true
    line, column := 1, 1
    if source != "" {
        line, column, _, _ = source_position(source, span.start)
    }
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t\t\t%s\n", kind, name, line, column, detail, file_path)
}

symbols_write_local_typed_fields :: proc(
    builder: ^strings.Builder,
    seen: ^map[string]bool,
    file_path, source: string,
    forms: []CST_Top_Form,
    local_name: string,
    span: Span,
    ty: string,
) {
    symbols_write_editor_record(builder, seen, "local", local_name, source, span, ty, file_path)
    fields, ok_fields := symbols_struct_fields_for_type(forms, ty)
    if !ok_fields {
        return
    }
    defer delete(fields)
    for field in fields {
        field_name := field.source_name
        if field_name == "" {
            field_name = field.name
        }
        name := fmt.tprintf("%s.%s", local_name, field_name)
        symbols_write_editor_record(builder, seen, "field", name, source, span, ty, file_path)
        delete(name)
    }
}

symbols_local_var_binding :: proc(form: CST_Form, bindings: []Local_Type_Binding) -> (name, ty: string, span: Span, ok: bool) {
    if form.kind != .List || len(form.items) < 3 || !is_symbol(form.items[0], "defvar") {
        return "", "", {}, false
    }
    target := form.items[1]
    if target.kind != .Symbol {
        return "", "", {}, false
    }
    raw_name := target.text
    value_index := 2
    if len(raw_name) > 0 && raw_name[len(raw_name)-1] == ':' {
        if len(raw_name) == 1 {
            return "", "", {}, false
        }
        parsed_ty, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 2)
        if !ok_type || next_i >= len(form.items) {
            _ = err_type
            return "", "", {}, false
        }
        value_index = next_i
        raw_name = raw_name[:len(raw_name)-1]
        return raw_name, parsed_ty, target.span, true
    }
    if value_index >= len(form.items) {
        return "", "", {}, false
    }
    inferred_ty, ok_ty := symbols_obvious_local_value_type(form.items[value_index], bindings)
    if !ok_ty {
        return "", "", {}, false
    }
    return raw_name, inferred_ty, target.span, true
}

symbols_collect_local_field_records_for_form :: proc(
    builder: ^strings.Builder,
    seen: ^map[string]bool,
    file_path, source: string,
    top_forms: []CST_Top_Form,
    form: CST_Form,
    bindings: ^[dynamic]Local_Type_Binding,
) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        for item in form.items {
            symbols_collect_local_field_records_for_form(builder, seen, file_path, source, top_forms, item, bindings)
        }
        return
    }

    head := form.items[0].text
    if head == "defn" || head == "defn-" {
        proc_form := form
        if len(form.items) > 3 && form.items[2].kind == .String {
            items: [dynamic]CST_Form
            defer delete(items)
            append(&items, form.items[0], form.items[1])
            for item in form.items[3:] {
                append(&items, item)
            }
            proc_form = CST_Form{kind = .List, items = items, span = form.span}
        }
        decl, err_proc, ok_proc := parse_proc_decl(proc_form)
        if ok_proc {
            local_bindings: [dynamic]Local_Type_Binding
            defer delete(local_bindings)
            for param in decl.params {
                if param.name != "" && param.ty != "" {
                    symbols_local_type_bind(&local_bindings, param.name, param.ty)
                    symbols_write_local_typed_fields(builder, seen, file_path, source, top_forms, param.name, form.span, param.ty)
                }
            }
            symbols_collect_local_field_records_for_forms(builder, seen, file_path, source, top_forms, decl.body[:], &local_bindings)
        } else {
            _ = err_proc
        }
        return
    }

    if head == "defvar" {
        name, ty, span, ok_var := symbols_local_var_binding(form, bindings[:])
        if ok_var {
            symbols_local_type_bind(bindings, name, ty)
            symbols_write_local_typed_fields(builder, seen, file_path, source, top_forms, name, span, ty)
        }
    }

    for item in form.items[1:] {
        symbols_collect_local_field_records_for_form(builder, seen, file_path, source, top_forms, item, bindings)
    }
}

symbols_collect_local_field_records_for_forms :: proc(
    builder: ^strings.Builder,
    seen: ^map[string]bool,
    file_path, source: string,
    top_forms: []CST_Top_Form,
    forms: []CST_Form,
    bindings: ^[dynamic]Local_Type_Binding,
) {
    for form in forms {
        symbols_collect_local_field_records_for_form(builder, seen, file_path, source, top_forms, form, bindings)
    }
}

symbols_append_local_field_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, file_path, source: string, forms: []CST_Top_Form) {
    bindings: [dynamic]Local_Type_Binding
    defer delete(bindings)
    for top in forms {
        symbols_collect_local_field_records_for_form(builder, seen, file_path, source, forms, top.form, &bindings)
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
            } else if key.kind == .Symbol && len(key.text) > 1 && key.text[len(key.text)-1] == ':' {
                name := fmt.tprintf("%s.%s", parent, key.text[:len(key.text)-1])
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
        } else if key.kind == .Symbol && len(key.text) > 1 && key.text[len(key.text)-1] == ':' {
            name := fmt.tprintf("%s.%s", parent, key.text[:len(key.text)-1])
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
    defer delete_borrowed_cst_top_form_slice(&forms)
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
        case "def", "def-":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                name := form.items[1].text
                if len(name) > 0 && name[len(name)-1] == ':' {
                    name = name[:len(name)-1]
                }
                doc_lines := top.doc_lines
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                detail := ""
                if head == "def-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "const", name, source, form.items[1].span, detail, "", doc_lines[:])
            }
        case "defvar", "defvar-":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                name := form.items[1].text
                if len(name) > 0 && name[len(name)-1] == ':' {
                    name = name[:len(name)-1]
                }
                doc_lines := top.doc_lines
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                detail := ""
                if head == "defvar-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "var", name, source, form.items[1].span, detail, "", doc_lines[:])
            }
        case "defstruct", "defstruct-":
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
                detail := ""
                if head == "defstruct-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "struct", name, source, form.items[1].span, detail, signature, doc_lines[:])
                symbols_write_fields(&builder, source, name, form.items[field_index])
            }
        case "defstate":
            if (len(form.items) == 3 || len(form.items) == 4 || len(form.items) == 5) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                field_index := 2
                if len(form.items) >= 4 && form.items[2].kind == .String {
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
                symbols_write_record_doc(&builder, "struct", name, source, form.items[1].span, "state", signature, doc_lines[:])
                symbols_write_fields(&builder, source, name, form.items[field_index])
            }
        case "defenum", "defenum-":
            if (len(form.items) == 3 || len(form.items) == 4) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                variant_index := 2
                if len(form.items) == 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    variant_index = 3
                }
                detail := ""
                if head == "defenum-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "enum", name, source, form.items[1].span, detail, "", doc_lines[:])
                symbols_write_enum_variants(&builder, source, name, form.items[variant_index])
            }
        case "defunion", "defunion-":
            if (len(form.items) == 3 || len(form.items) == 4) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                variant_index := 2
                if len(form.items) == 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    variant_index = 3
                }
                detail := ""
                if head == "defunion-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "union", name, source, form.items[1].span, detail, "", doc_lines[:])
                symbols_write_union_variants(&builder, source, name, form.items[variant_index])
            }
        case "defn", "defn-":
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
                detail := ""
                if head == "defn-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "proc", form.items[1].text, source, form.items[1].span, detail, signature, doc_lines[:])
            }
        case "defmacro", "defmacro-":
            if len(form.items) >= 3 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                signature := fmt.tprintf("(%s ...)", form.items[1].text)
                if len(form.items) >= 3 && form.items[2].kind == .Vector {
                    signature = fmt.tprintf("(%s %s)", form.items[1].text, macro_form_text(form.items[2]))
                } else if len(form.items) >= 4 && form.items[3].kind == .Vector {
                    signature = fmt.tprintf("(%s %s)", form.items[1].text, macro_form_text(form.items[3]))
                }
                detail := ""
                if head == "defmacro-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "macro", form.items[1].text, source, form.items[1].span, detail, signature, doc_lines[:])
            }
        case "defsource", "defsource-":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                signature := ""
                source_decl, err_source, ok_source := parse_source_decl(form)
                if ok_source {
                    signature = symbols_source_signature(form.items[1].text, source_decl)
                } else {
                    _ = err_source
                }
                detail := ""
                if head == "defsource-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "source", form.items[1].text, source, form.items[1].span, detail, signature, top.doc_lines[:])
            }
        case:
        }
    }

    context.allocator = result_allocator
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}
