// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:strings"

is_whitespace :: proc(ch: byte) -> bool {
    return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

is_delimiter :: proc(ch: byte) -> bool {
    return is_whitespace(ch) || ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}' || ch == ',' || ch == ';'
}

is_symbol_boundary :: proc(ch: byte) -> bool {
    return is_whitespace(ch) || ch == '(' || ch == ')' || ch == '{' || ch == '}' || ch == ',' || ch == ';'
}

is_digit :: proc(ch: byte) -> bool {
    return ch >= '0' && ch <= '9'
}

make_span :: proc(start, end: int, source_kind: Source_Kind) -> Span {
    return Span{start = start, end = end, source = source_kind}
}

make_token :: proc(kind: Token_Kind, text: string, start, end: int, source_kind: Source_Kind) -> Token {
    return Token{
        kind = kind,
        text = text,
        span = make_span(start, end, source_kind),
    }
}

scan_compact_bracket_type :: proc(source: string, start: int) -> (end: int, ok: bool) {
    i := start
    if source[start] == '^' {
        if start+1 >= len(source) || source[start+1] != '[' {
            return start, false
        }
        i = start + 1
    }
    for i < len(source) && source[i] == '[' {
        i += 1
        for i < len(source) && source[i] != ']' {
            if is_whitespace(source[i]) || source[i] == '(' || source[i] == ')' || source[i] == '{' || source[i] == '}' || source[i] == ',' || source[i] == ';' {
                return start, false
            }
            i += 1
        }
        if i >= len(source) || source[i] != ']' {
            return start, false
        }
        i += 1
    }
    if i >= len(source) || is_symbol_boundary(source[i]) || source[i] == ']' || source[i] == '.' {
        return start, false
    }
    for i < len(source) && !is_delimiter(source[i]) {
        i += 1
    }
    return i, true
}

scan_compact_soa_type :: proc(source: string, start: int) -> (end: int, ok: bool) {
    prefix := "#soa["
    body_start := start
    if start+1 < len(source) && source[start] == '^' && source[start+1] == '#' {
        body_start = start + 1
    }
    if body_start+len(prefix) > len(source) || source[body_start:body_start+len(prefix)] != prefix {
        return start, false
    }
    i := body_start + len(prefix)
    for i < len(source) && source[i] != ']' {
        if is_whitespace(source[i]) || source[i] == '(' || source[i] == ')' || source[i] == '{' || source[i] == '}' || source[i] == ',' || source[i] == ';' {
            return start, false
        }
        i += 1
    }
    if i >= len(source) || source[i] != ']' {
        return start, false
    }
    i += 1
    if i >= len(source) || is_symbol_boundary(source[i]) || source[i] == '[' || source[i] == ']' {
        return start, false
    }
    for i < len(source) && !is_delimiter(source[i]) {
        i += 1
    }
    return i, true
}

scan_compact_simd_type :: proc(source: string, start: int) -> (end: int, ok: bool) {
    prefix := "#simd["
    body_start := start
    if start+1 < len(source) && source[start] == '^' && source[start+1] == '#' {
        body_start = start + 1
    }
    if body_start+len(prefix) > len(source) || source[body_start:body_start+len(prefix)] != prefix {
        return start, false
    }
    i := body_start + len(prefix)
    for i < len(source) && source[i] != ']' {
        if is_whitespace(source[i]) || source[i] == '(' || source[i] == ')' || source[i] == '{' || source[i] == '}' || source[i] == ',' || source[i] == ';' {
            return start, false
        }
        i += 1
    }
    if i >= len(source) || source[i] != ']' {
        return start, false
    }
    i += 1
    if i >= len(source) || is_symbol_boundary(source[i]) || source[i] == '[' || source[i] == ']' {
        return start, false
    }
    for i < len(source) && !is_delimiter(source[i]) {
        i += 1
    }
    return i, true
}

scan_compact_bit_set_type :: proc(source: string, start: int) -> (end: int, ok: bool) {
    prefix := "bit_set["
    body_start := start
    if source[start] == '^' {
        body_start = start + 1
    }
    if body_start+len(prefix) > len(source) || source[body_start:body_start+len(prefix)] != prefix {
        return start, false
    }
    i := body_start + len(prefix)
    for i < len(source) && source[i] != ']' {
        if source[i] == '(' || source[i] == ')' || source[i] == '{' || source[i] == '}' {
            return start, false
        }
        i += 1
    }
    if i >= len(source) || source[i] != ']' {
        return start, false
    }
    i += 1
    if i < len(source) && !is_delimiter(source[i]) {
        return start, false
    }
    return i, true
}

scan_compact_map_type :: proc(source: string, start: int) -> (end: int, ok: bool) {
    body_start := start
    if source[start] == '^' {
        body_start = start + 1
    }
    if body_start+4 > len(source) || source[body_start:body_start+4] != "map[" {
        return start, false
    }
    i := body_start + 4
    for i < len(source) && source[i] != ']' {
        if is_whitespace(source[i]) || source[i] == '(' || source[i] == ')' || source[i] == '{' || source[i] == '}' || source[i] == ',' || source[i] == ';' {
            return start, false
        }
        i += 1
    }
    if i >= len(source) || source[i] != ']' {
        return start, false
    }
    i += 1
    if i >= len(source) || is_symbol_boundary(source[i]) || source[i] == '[' || source[i] == ']' {
        return start, false
    }
    for i < len(source) && !is_delimiter(source[i]) {
        i += 1
    }
    return i, true
}

scan_compact_matrix_type :: proc(source: string, start: int) -> (end: int, ok: bool) {
    prefix := "matrix["
    body_start := start
    if source[start] == '^' {
        body_start = start + 1
    }
    if body_start+len(prefix) > len(source) || source[body_start:body_start+len(prefix)] != prefix {
        return start, false
    }
    i := body_start + len(prefix)
    for i < len(source) && source[i] != ']' {
        if source[i] == '(' || source[i] == ')' || source[i] == '{' || source[i] == '}' || source[i] == ';' {
            return start, false
        }
        i += 1
    }
    if i >= len(source) || source[i] != ']' {
        return start, false
    }
    i += 1
    if i >= len(source) || is_symbol_boundary(source[i]) || source[i] == '[' || source[i] == ']' {
        return start, false
    }
    for i < len(source) && !is_delimiter(source[i]) {
        i += 1
    }
    return i, true
}

scan_compact_set_type :: proc(source: string, start: int) -> (end: int, ok: bool) {
    body_start := start
    if source[start] == '^' {
        body_start = start + 1
    }
    if body_start+4 > len(source) || source[body_start:body_start+4] != "set[" {
        return start, false
    }
    i := body_start + 4
    for i < len(source) && source[i] != ']' {
        if is_whitespace(source[i]) || source[i] == '(' || source[i] == ')' || source[i] == '{' || source[i] == '}' || source[i] == ',' || source[i] == ';' {
            return start, false
        }
        i += 1
    }
    if i >= len(source) || source[i] != ']' {
        return start, false
    }
    i += 1
    if i < len(source) && !is_delimiter(source[i]) {
        return start, false
    }
    return i, true
}

scan_number :: proc(source: string, start: int) -> (end: int, ok: bool) {
    if start >= len(source) {
        return start, false
    }
    i := start
    if source[i] == '-' {
        if i+1 >= len(source) || !is_digit(source[i+1]) {
            return start, false
        }
        i += 1
    } else if !is_digit(source[i]) {
        return start, false
    }
    for i < len(source) && !is_delimiter(source[i]) {
        i += 1
    }
    return i, true
}

tokenize_with_origin :: proc(source: string, source_kind: Source_Kind) -> (tokens: [dynamic]Token, err: Compile_Error, ok: bool) {
    i := 0
    for i < len(source) {
        ch := source[i]
        if is_whitespace(ch) || ch == ',' {
            i += 1
            continue
        }
        if ch == ';' {
            start := i
            for i < len(source) && source[i] != '\n' {
                i += 1
            }
            append(&tokens, make_token(.Line_Comment, source[start:i], start, i, source_kind))
            continue
        }
        if ch == '/' && i+1 < len(source) && source[i+1] == '/' {
            start := i
            i += 2
            for i < len(source) && source[i] != '\n' {
                i += 1
            }
            append(&tokens, make_token(.Line_Comment, source[start:i], start, i, source_kind))
            continue
        }
        if ch == '/' && i+1 < len(source) && source[i+1] == '*' {
            start := i
            i += 2
            for i+1 < len(source) && !(source[i] == '*' && source[i+1] == '/') {
                i += 1
            }
            if i+1 >= len(source) {
                return tokens, Compile_Error{message = "unterminated block comment", span = make_span(start, len(source), source_kind)}, false
            }
            i += 2
            append(&tokens, make_token(.Block_Comment, source[start:i], start, i, source_kind))
            continue
        }
        start := i
        if ch == '[' || ch == '^' {
            end, ok_type := scan_compact_bracket_type(source, start)
            if ok_type {
                append(&tokens, make_token(.Symbol, source[start:end], start, end, source_kind))
                i = end
                continue
            }
        }
        if ch == '#' || ch == '^' {
            simd_end, ok_simd_type := scan_compact_simd_type(source, start)
            if ok_simd_type {
                append(&tokens, make_token(.Symbol, source[start:simd_end], start, simd_end, source_kind))
                i = simd_end
                continue
            }
            soa_end, ok_soa_type := scan_compact_soa_type(source, start)
            if ok_soa_type {
                append(&tokens, make_token(.Symbol, source[start:soa_end], start, soa_end, source_kind))
                i = soa_end
                continue
            }
        }
        if ch == 'b' || ch == '^' {
            end, ok_type := scan_compact_bit_set_type(source, start)
            if ok_type {
                append(&tokens, make_token(.Symbol, source[start:end], start, end, source_kind))
                i = end
                continue
            }
        }
        if ch == 'm' || ch == '^' {
            matrix_end, ok_matrix_type := scan_compact_matrix_type(source, start)
            if ok_matrix_type {
                append(&tokens, make_token(.Symbol, source[start:matrix_end], start, matrix_end, source_kind))
                i = matrix_end
                continue
            }
            map_end, ok_map_type := scan_compact_map_type(source, start)
            if ok_map_type {
                append(&tokens, make_token(.Symbol, source[start:map_end], start, map_end, source_kind))
                i = map_end
                continue
            }
        }
        if ch == 's' || ch == '^' {
            end, ok_type := scan_compact_set_type(source, start)
            if ok_type {
                append(&tokens, make_token(.Symbol, source[start:end], start, end, source_kind))
                i = end
                continue
            }
        }
        if end, ok_number := scan_number(source, start); ok_number {
            append(&tokens, make_token(.Number, source[start:end], start, end, source_kind))
            i = end
            continue
        }
        switch ch {
        case '(':
            append(&tokens, make_token(.L_Paren, "(", start, start+1, source_kind))
            i += 1
            continue
        case ')':
            append(&tokens, make_token(.R_Paren, ")", start, start+1, source_kind))
            i += 1
            continue
        case '[':
            append(&tokens, make_token(.L_Bracket, "[", start, start+1, source_kind))
            i += 1
            continue
        case ']':
            append(&tokens, make_token(.R_Bracket, "]", start, start+1, source_kind))
            i += 1
            continue
        case '{':
            append(&tokens, make_token(.L_Brace, "{", start, start+1, source_kind))
            i += 1
            continue
        case '}':
            append(&tokens, make_token(.R_Brace, "}", start, start+1, source_kind))
            i += 1
            continue
        case '"':
            i += 1
            escaped := false
            for i < len(source) {
                c := source[i]
                if escaped {
                    escaped = false
                } else if c == '\\' {
                    escaped = true
                } else if c == '"' {
                    i += 1
                    append(&tokens, make_token(.String, source[start:i], start, i, source_kind))
                    break
                }
                i += 1
            }
            if len(tokens) == 0 || tokens[len(tokens)-1].span.start != start {
                return tokens, Compile_Error{message = "unterminated string literal", span = make_span(start, len(source), source_kind)}, false
            }
            continue
        case '#':
            if i+1 < len(source) && source[i+1] == '{' {
                append(&tokens, make_token(.L_Set_Brace, "#{", start, start+2, source_kind))
                i += 2
                continue
            }
            if i+1 < len(source) && source[i+1] == '_' {
                append(&tokens, make_token(.Discard, "#_", start, start+2, source_kind))
                i += 2
                continue
            }
        }

        if ch == ':' {
            i += 1
            for i < len(source) && !is_delimiter(source[i]) {
                if source[i] == '/' && i+1 < len(source) && source[i+1] == '/' {
                    break
                }
                i += 1
            }
            append(&tokens, make_token(.Keyword, source[start:i], start, i, source_kind))
            continue
        }

        for i < len(source) && !is_delimiter(source[i]) {
            if source[i] == '/' && i+1 < len(source) && source[i+1] == '/' {
                break
            }
            i += 1
        }
        text := source[start:i]
        if text == "true" || text == "false" {
            append(&tokens, make_token(.Bool, text, start, i, source_kind))
        } else if text == "nil" {
            append(&tokens, make_token(.Nil, text, start, i, source_kind))
        } else {
            append(&tokens, make_token(.Symbol, text, start, i, source_kind))
        }
    }

    append(&tokens, make_token(.EOF, "", len(source), len(source), source_kind))
    return tokens, {}, true
}

tokenize :: proc(source: string) -> (tokens: [dynamic]Token, err: Compile_Error, ok: bool) {
    return tokenize_with_origin(source, .File)
}

delimiter_text :: proc(kind: Token_Kind) -> string {
    #partial switch kind {
    case .L_Paren:
        return "("
    case .R_Paren:
        return ")"
    case .L_Bracket:
        return "["
    case .R_Bracket:
        return "]"
    case .L_Brace, .L_Set_Brace:
        return "{"
    case .R_Brace:
        return "}"
    case:
        return "delimiter"
    }
}

parse_container :: proc(tokens: []Token, index: ^int, open_kind, close_kind: Token_Kind, out_kind: CST_Form_Kind) -> (form: CST_Form, err: Compile_Error, ok: bool) {
    start := tokens[index^].span.start
    source_kind := tokens[index^].span.source
    index^ += 1
    items: [dynamic]CST_Form
    for index^ < len(tokens) && tokens[index^].kind != close_kind && tokens[index^].kind != .EOF {
        if tokens[index^].kind == .Discard {
            index^ += 1
            skipped, err_skip, ok_skip := parse_form(tokens, index)
            if !ok_skip {
                delete_borrowed_cst_form_slice(&items)
                return form, err_skip, false
            }
            delete_borrowed_cst_form(&skipped)
            continue
        }
        if tokens[index^].kind == .Line_Comment || tokens[index^].kind == .Block_Comment {
            index^ += 1
            continue
        }
        item, err_item, ok_item := parse_form(tokens, index)
        if !ok_item {
            delete_borrowed_cst_form_slice(&items)
            return form, err_item, false
        }
        append(&items, item)
    }
    if index^ >= len(tokens) || tokens[index^].kind != close_kind {
        delete_borrowed_cst_form_slice(&items)
        return form, Compile_Error{message = fmt.tprintf("missing closing delimiter `%s` for `%s` opened here", delimiter_text(close_kind), delimiter_text(open_kind)), span = make_span(start, start, source_kind)}, false
    }
    end := tokens[index^].span.end
    index^ += 1
    return CST_Form{
        kind = out_kind,
        items = items,
        span = make_span(start, end, source_kind),
    }, {}, true
}

parse_primary_form :: proc(tokens: []Token, index: ^int) -> (form: CST_Form, err: Compile_Error, ok: bool) {
    if index^ >= len(tokens) {
        return form, Compile_Error{message = "unexpected end of input"}, false
    }
    token := tokens[index^]
    #partial switch token.kind {
    case .L_Paren:
        return parse_container(tokens, index, .L_Paren, .R_Paren, .List)
    case .L_Bracket:
        return parse_container(tokens, index, .L_Bracket, .R_Bracket, .Vector)
    case .L_Brace:
        return parse_container(tokens, index, .L_Brace, .R_Brace, .Brace)
    case .L_Set_Brace:
        return parse_container(tokens, index, .L_Set_Brace, .R_Brace, .Set)
    case .String:
        index^ += 1
        return CST_Form{kind = .String, text = token.text, span = token.span}, {}, true
    case .Number:
        index^ += 1
        return CST_Form{kind = .Number, text = token.text, span = token.span}, {}, true
    case .Bool:
        index^ += 1
        return CST_Form{kind = .Bool, text = token.text, span = token.span}, {}, true
    case .Nil:
        index^ += 1
        return CST_Form{kind = .Nil, text = token.text, span = token.span}, {}, true
    case .Symbol:
        index^ += 1
        return CST_Form{kind = .Symbol, text = token.text, span = token.span}, {}, true
    case .Keyword:
        index^ += 1
        return CST_Form{kind = .Keyword, text = token.text, span = token.span}, {}, true
    case .Line_Comment, .Block_Comment:
        index^ += 1
        return parse_form(tokens, index)
    case .Discard:
        index^ += 1
        skipped, err_skip, ok_skip := parse_form(tokens, index)
        if !ok_skip {
            return form, err_skip, false
        }
        delete_borrowed_cst_form(&skipped)
        return parse_form(tokens, index)
    case .R_Paren, .R_Bracket, .R_Brace:
        return form, Compile_Error{message = fmt.tprintf("unexpected closing delimiter `%s`", delimiter_text(token.kind)), span = token.span}, false
    case .EOF:
        return form, Compile_Error{message = "unexpected end of input", span = token.span}, false
    }
    return form, Compile_Error{message = "unsupported token", span = token.span}, false
}

token_is_attached_field_postfix :: proc(token: Token, base: CST_Form) -> bool {
    return token.kind == .Symbol &&
           token.span.start == base.span.end &&
           len(token.text) > 1 &&
           token.text[0] == '.'
}

omitted_slice_bound_form :: proc(span: Span) -> CST_Form {
    return CST_Form{kind = .Symbol, text = "__kvist_omitted", span = span}
}

form_from_compact_slice_part :: proc(text: string, span: Span) -> CST_Form {
    if len(text) == 0 {
        return omitted_slice_bound_form(span)
    }
    if text == "true" || text == "false" {
        return CST_Form{kind = .Bool, text = text, span = span}
    }
    if text == "nil" {
        return CST_Form{kind = .Nil, text = text, span = span}
    }
    if number_end, ok_number := scan_number(text, 0); ok_number && number_end == len(text) {
        return CST_Form{kind = .Number, text = text, span = span}
    }
    return CST_Form{kind = .Symbol, text = text, span = span}
}

split_compact_slice_form :: proc(form: CST_Form) -> (start, end: CST_Form, ok: bool) {
    if form.kind == .Keyword {
        if form.text == ":" {
            return omitted_slice_bound_form(form.span), omitted_slice_bound_form(form.span), true
        }
        if len(form.text) > 1 {
            return omitted_slice_bound_form(form.span), form_from_compact_slice_part(form.text[1:], form.span), true
        }
        return {}, {}, false
    }
    if form.kind != .Symbol && form.kind != .Number {
        return {}, {}, false
    }
    colon := strings.index(form.text, ":")
    if colon < 0 {
        return {}, {}, false
    }
    rest := form.text[colon+1:]
    if strings.index(rest, ":") >= 0 {
        return {}, {}, false
    }
    return form_from_compact_slice_part(form.text[:colon], form.span), form_from_compact_slice_part(rest, form.span), true
}

attached_slice_bounds :: proc(items: []CST_Form) -> (start, end: CST_Form, ok: bool) {
    if len(items) == 1 {
        return split_compact_slice_form(items[0])
    }
    if len(items) == 2 {
        if compact_start, compact_end, ok_compact := split_compact_slice_form(items[0]); ok_compact {
            if compact_end.kind == .Symbol && compact_end.text == "__kvist_omitted" {
                return compact_start, items[1], true
            }
        }
        if items[0].kind == .Keyword && items[0].text == ":" {
            return omitted_slice_bound_form(items[0].span), items[1], true
        }
        if items[1].kind == .Keyword {
            if items[1].text == ":" {
                return items[0], omitted_slice_bound_form(items[1].span), true
            }
            if len(items[1].text) > 1 {
                return items[0], form_from_compact_slice_part(items[1].text[1:], items[1].span), true
            }
        }
    }
    if len(items) == 3 && items[1].kind == .Keyword && items[1].text == ":" {
        return items[0], items[2], true
    }
    return {}, {}, false
}

parse_attached_postfix :: proc(tokens: []Token, index: ^int, base: CST_Form) -> (form: CST_Form, err: Compile_Error, ok: bool) {
    current := base
    for index^ < len(tokens) {
        if token_is_attached_field_postfix(tokens[index^], current) {
            token := tokens[index^]
            index^ += 1
            list_items: [dynamic]CST_Form
            append(&list_items, CST_Form{kind = .Symbol, text = "__kvist_field", span = token.span})
            append(&list_items, current)
            append(&list_items, CST_Form{kind = .Symbol, text = token.text[1:], span = token.span})
            current = CST_Form{
                kind = .List,
                items = list_items,
                span = make_span(current.span.start, token.span.end, token.span.source),
            }
            continue
        }
        if tokens[index^].kind != .L_Bracket || tokens[index^].span.start != current.span.end {
            break
        }
        open := tokens[index^]
        source_kind := open.span.source
        index^ += 1
            items: [dynamic]CST_Form
            for index^ < len(tokens) && tokens[index^].kind != .R_Bracket && tokens[index^].kind != .EOF {
                if tokens[index^].kind == .Discard {
                    index^ += 1
                    skipped, err_skip, ok_skip := parse_form(tokens, index)
                    if !ok_skip {
                        delete_borrowed_cst_form(&current)
                        delete_borrowed_cst_form_slice(&items)
                        return form, err_skip, false
                    }
                    delete_borrowed_cst_form(&skipped)
                    continue
                }
                if tokens[index^].kind == .Line_Comment || tokens[index^].kind == .Block_Comment {
                    index^ += 1
                    continue
                }
                item, err_item, ok_item := parse_form(tokens, index)
                if !ok_item {
                    delete_borrowed_cst_form(&current)
                    delete_borrowed_cst_form_slice(&items)
                    return form, err_item, false
                }
                append(&items, item)
            }
            if index^ >= len(tokens) || tokens[index^].kind != .R_Bracket {
                delete_borrowed_cst_form(&current)
                delete_borrowed_cst_form_slice(&items)
                return form, Compile_Error{message = "missing closing delimiter `]` for `[` opened here", span = make_span(open.span.start, open.span.start, source_kind)}, false
            }
            close := tokens[index^]
            index^ += 1
            if start, end, ok_slice := attached_slice_bounds(items[:]); ok_slice {
            list_items: [dynamic]CST_Form
            append(&list_items, CST_Form{kind = .Symbol, text = "__kvist_slice", span = open.span})
            append(&list_items, current)
            append(&list_items, start)
            append(&list_items, end)
            current = CST_Form{
                    kind = .List,
                    items = list_items,
                    span = make_span(current.span.start, close.span.end, source_kind),
                }
                delete(items)
                continue
            }
            if len(items) != 1 {
                delete_borrowed_cst_form(&current)
                delete_borrowed_cst_form_slice(&items)
                return form, Compile_Error{message = "attached index expects exactly one expression", span = make_span(open.span.start, close.span.end, source_kind)}, false
            }
        list_items: [dynamic]CST_Form
        append(&list_items, CST_Form{kind = .Symbol, text = "__kvist_index", span = open.span})
        append(&list_items, current)
        append(&list_items, items[0])
        current = CST_Form{
                kind = .List,
                items = list_items,
                span = make_span(current.span.start, close.span.end, source_kind),
            }
            delete(items)
        }
        return current, {}, true
}

parse_form :: proc(tokens: []Token, index: ^int) -> (form: CST_Form, err: Compile_Error, ok: bool) {
    primary, err_primary, ok_primary := parse_primary_form(tokens, index)
    if !ok_primary {
        return form, err_primary, false
    }
    return parse_attached_postfix(tokens, index, primary)
}

is_doc_comment :: proc(text: string) -> bool {
    return len(text) >= 2 && text[0] == '/' && text[1] == '/' ||
           len(text) >= 2 && text[0] == '/' && text[1] == '*' ||
           len(text) >= 1 && text[0] == ';'
}

trim_doc_text :: proc(text: string) -> string {
    start := 0
    end := len(text)
    for start < end && (text[start] == ' ' || text[start] == '\t' || text[start] == '\r') {
        start += 1
    }
    for end > start && (text[end-1] == ' ' || text[end-1] == '\t' || text[end-1] == '\r') {
        end -= 1
    }
    return text[start:end]
}

block_doc_line_text :: proc(line: string) -> string {
    text := trim_doc_text(line)
    if len(text) > 0 && text[0] == '*' {
        text = text[1:]
        text = trim_doc_text(text)
    }
    return text
}

block_doc_comment_text :: proc(text: string) -> string {
    if len(text) < 4 {
        return text
    }

    body := text[2:len(text)-2]
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    seen_content := false
    pending_blank := false
    start := 0
    for start <= len(body) {
        end := start
        for end < len(body) && body[end] != '\n' {
            end += 1
        }
        line := block_doc_line_text(body[start:end])
        if len(line) == 0 {
            if seen_content {
                pending_blank = true
            }
        } else {
            if seen_content {
                strings.write_byte(&builder, '\n')
            }
            if pending_blank {
                strings.write_byte(&builder, '\n')
            }
            strings.write_string(&builder, line)
            seen_content = true
            pending_blank = false
        }
        if end >= len(body) {
            break
        }
        start = end + 1
    }
    return strings.clone(strings.to_string(builder))
}

doc_comment_text :: proc(text: string) -> string {
    if len(text) >= 1 && text[0] == ';' {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, "//")
        strings.write_string(&builder, text[1:])
        return strings.clone(strings.to_string(builder))
    }
    if len(text) >= 2 && text[0] == '/' && text[1] == '*' {
        return block_doc_comment_text(text)
    }
    return strings.clone(text)
}

has_blank_line_between :: proc(source: string, start, end: int) -> bool {
    newlines := 0
    i := start
    for i < end {
        if source[i] == '\n' {
            newlines += 1
            if newlines > 1 {
                return true
            }
        }
        i += 1
    }
    return false
}

read_top_forms_with_origin :: proc(source: string, source_kind: Source_Kind) -> (forms: [dynamic]CST_Top_Form, err: Compile_Error, ok: bool) {
    tokens, err_tok, ok_tok := tokenize_with_origin(source, source_kind)
    if !ok_tok {
        delete(tokens)
        return forms, err_tok, false
    }
    defer delete(tokens)

    index := 0
    pending_docs: [dynamic]string
    last_doc_end := 0
    for index < len(tokens) && tokens[index].kind != .EOF {
        if tokens[index].kind == .Line_Comment || tokens[index].kind == .Block_Comment {
            if is_doc_comment(tokens[index].text) {
                append(&pending_docs, doc_comment_text(tokens[index].text))
                last_doc_end = tokens[index].span.end
            } else {
                delete_string_slice(&pending_docs)
            }
            index += 1
            continue
        }
        if tokens[index].kind == .Discard {
            delete_string_slice(&pending_docs)
            index += 1
            skipped, err_skip, ok_skip := parse_form(tokens[:], &index)
            if !ok_skip {
                delete_borrowed_cst_top_form_slice(&forms)
                return forms, err_skip, false
            }
            delete_borrowed_cst_form(&skipped)
            continue
        }
        form, err_form, ok_form := parse_form(tokens[:], &index)
        if !ok_form {
            delete_string_slice(&pending_docs)
            delete_borrowed_cst_top_form_slice(&forms)
            return forms, err_form, false
        }
        doc_lines: [dynamic]string
        if len(pending_docs) > 0 && !has_blank_line_between(source, last_doc_end, form.span.start) {
            doc_lines = pending_docs
        } else {
            delete_string_slice(&pending_docs)
        }
        append(&forms, CST_Top_Form{
            form = form,
            doc_lines = doc_lines,
            source = source[form.span.start:form.span.end],
        })
        pending_docs = nil
    }
    delete_string_slice(&pending_docs)
    return forms, {}, true
}

read_top_forms :: proc(source: string) -> (forms: [dynamic]CST_Top_Form, err: Compile_Error, ok: bool) {
    return read_top_forms_with_origin(source, .File)
}

unquote_string :: proc(text: string) -> string {
    if len(text) < 2 || text[0] != '"' || text[len(text)-1] != '"' {
        return text
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    i := 1
    for i < len(text)-1 {
        if text[i] == '\\' && i+1 < len(text)-1 {
            i += 1
            switch text[i] {
            case 'n':
                strings.write_byte(&builder, '\n')
            case 'r':
                strings.write_byte(&builder, '\r')
            case 't':
                strings.write_byte(&builder, '\t')
            case '"':
                strings.write_byte(&builder, '"')
            case '\\':
                strings.write_byte(&builder, '\\')
            case:
                strings.write_byte(&builder, text[i])
            }
        } else {
            strings.write_byte(&builder, text[i])
        }
        i += 1
    }
    return strings.clone(strings.to_string(builder))
}

map_name :: proc(text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for ch in text {
        if ch == '-' {
            strings.write_byte(&builder, '_')
        } else if ch == '?' {
            strings.write_string(&builder, "_p")
        } else if ch == '!' {
            strings.write_string(&builder, "_bang")
        } else {
            strings.write_byte(&builder, byte(ch))
        }
    }
    return strings.clone(strings.to_string(builder))
}
