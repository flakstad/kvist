package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "base:runtime"

import_entry_from_form :: proc(form: CST_Form) -> (Imported_Symbol_Entry, bool) {
    if form.kind != .List || len(form.items) == 0 || !is_symbol(form.items[0], "import") {
        return {}, false
    }
    if len(form.items) == 2 && form.items[1].kind == .String {
        return {}, false
    }
    if source_import_form_has_refer(form) {
        path := import_path_text(form.items[1])
        alias := import_default_alias(path)
        if as_index, has_as := source_import_as_index(form); has_as {
            alias = map_name(form.items[as_index].text)
        }
        if alias == "" {
            return {}, false
        }
        return Imported_Symbol_Entry{alias = alias, path = path}, true
    }
    if import_form_has_as(form) {
        path := import_path_text(form.items[1])
        as_index, _ := source_import_as_index(form)
        return Imported_Symbol_Entry{alias = map_name(form.items[as_index].text), path = path}, true
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
    case os.is_absolute_path(import_path):
        if os.exists(import_path) && os.is_dir(import_path) {
            return strings.clone(import_path), true
        }
        return "", false
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
    if strings.has_prefix(text, ";") {
        idx := 0
        for idx < len(text) && text[idx] == ';' {
            idx += 1
        }
        return strings.trim_left(text[idx:], " \t")
    }
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
        case strings.has_prefix(trimmed, ";"):
            append(&docs, odin_clean_doc_comment_line(line))
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
