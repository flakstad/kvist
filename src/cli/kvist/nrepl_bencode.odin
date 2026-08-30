// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:strconv"
import "core:strings"

NREPL_MAX_MESSAGE_BYTES :: 16 * 1024 * 1024
NREPL_MAX_BENCODE_DEPTH :: 64

Nrepl_Decode_Status :: enum {
    Complete,
    Incomplete,
    Invalid,
}

Nrepl_Request :: struct {
    op:                 string,
    id:                 string,
    session:            string,
    code:               string,
    file:               string,
    file_name:          string,
    file_path:          string,
    prefix:             string,
    symbol:             string,
    sym:                string,
    completion_context: string,
    ns:                 string,
    interrupt_id:       string,
    stdin:              string,
    line:               int,
    column:             int,
    has_line:           bool,
    has_column:         bool,
}

nrepl_request_delete :: proc(request: ^Nrepl_Request) {
    delete(request.op)
    delete(request.id)
    delete(request.session)
    delete(request.code)
    delete(request.file)
    delete(request.file_name)
    delete(request.file_path)
    delete(request.prefix)
    delete(request.symbol)
    delete(request.sym)
    delete(request.completion_context)
    delete(request.ns)
    delete(request.interrupt_id)
    delete(request.stdin)
    request^ = {}
}

nrepl_bencode_read_string :: proc(
    data: []byte,
    position: ^int,
) -> (value: string, status: Nrepl_Decode_Status) {
    start := position^
    if start >= len(data) {
        return "", .Incomplete
    }
    if data[start] < '0' || data[start] > '9' {
        return "", .Invalid
    }

    colon := start
    for colon < len(data) && data[colon] != ':' {
        if data[colon] < '0' || data[colon] > '9' {
            return "", .Invalid
        }
        colon += 1
    }
    if colon >= len(data) {
        return "", .Incomplete
    }
    if colon > start+1 && data[start] == '0' {
        return "", .Invalid
    }
    size, ok_size := strconv.parse_int(string(data[start:colon]), 10)
    if !ok_size || size < 0 || size > NREPL_MAX_MESSAGE_BYTES {
        return "", .Invalid
    }
    value_start := colon+1
    if size > len(data)-value_start {
        return "", .Incomplete
    }
    value_end := value_start+size
    position^ = value_end
    return string(data[value_start:value_end]), .Complete
}

nrepl_bencode_read_integer :: proc(
    data: []byte,
    position: ^int,
) -> (value: int, status: Nrepl_Decode_Status) {
    start := position^
    if start >= len(data) {
        return 0, .Incomplete
    }
    if data[start] != 'i' {
        return 0, .Invalid
    }
    end := start+1
    for end < len(data) && data[end] != 'e' {
        end += 1
    }
    if end >= len(data) {
        return 0, .Incomplete
    }
    number := data[start+1:end]
    if len(number) == 0 ||
       (len(number) > 1 && number[0] == '0') ||
       number[0] == '+' ||
       (number[0] == '-' &&
        (len(number) == 1 || number[1] == '0')) {
        return 0, .Invalid
    }
    parsed, ok_parsed := strconv.parse_int(string(number), 10)
    if !ok_parsed {
        return 0, .Invalid
    }
    position^ = end+1
    return parsed, .Complete
}

nrepl_bencode_skip :: proc(
    data: []byte,
    position: ^int,
    depth := 0,
) -> Nrepl_Decode_Status {
    if depth > NREPL_MAX_BENCODE_DEPTH {
        return .Invalid
    }
    if position^ >= len(data) {
        return .Incomplete
    }
    switch data[position^] {
    case '0'..='9':
        _, status := nrepl_bencode_read_string(data, position)
        return status
    case 'i':
        _, status := nrepl_bencode_read_integer(data, position)
        return status
    case 'l':
        position^ += 1
        for {
            if position^ >= len(data) {
                return .Incomplete
            }
            if data[position^] == 'e' {
                position^ += 1
                return .Complete
            }
            status := nrepl_bencode_skip(data, position, depth+1)
            if status != .Complete {
                return status
            }
        }
    case 'd':
        position^ += 1
        for {
            if position^ >= len(data) {
                return .Incomplete
            }
            if data[position^] == 'e' {
                position^ += 1
                return .Complete
            }
            _, key_status := nrepl_bencode_read_string(data, position)
            if key_status != .Complete {
                return key_status
            }
            value_status := nrepl_bencode_skip(data, position, depth+1)
            if value_status != .Complete {
                return value_status
            }
        }
    }
    return .Invalid
}

nrepl_bencode_read_request_int :: proc(
    data: []byte,
    position: ^int,
) -> (value: int, status: Nrepl_Decode_Status) {
    if position^ >= len(data) {
        return 0, .Incomplete
    }
    if data[position^] == 'i' {
        return nrepl_bencode_read_integer(data, position)
    }
    text, text_status := nrepl_bencode_read_string(data, position)
    if text_status != .Complete {
        return 0, text_status
    }
    parsed, ok_value := strconv.parse_int(text, 10)
    if !ok_value {
        return 0, .Invalid
    }
    return parsed, .Complete
}

nrepl_bencode_decode_request :: proc(
    data: []byte,
) -> (
    request: Nrepl_Request,
    consumed: int,
    status: Nrepl_Decode_Status,
) {
    if len(data) == 0 {
        return request, 0, .Incomplete
    }
    if len(data) > NREPL_MAX_MESSAGE_BYTES {
        return request, 0, .Invalid
    }
    if data[0] != 'd' {
        return request, 0, .Invalid
    }

    position := 1
    for {
        if position >= len(data) {
            nrepl_request_delete(&request)
            return request, 0, .Incomplete
        }
        if data[position] == 'e' {
            position += 1
            if request.op == "" {
                nrepl_request_delete(&request)
                return request, 0, .Invalid
            }
            return request, position, .Complete
        }

        key, key_status := nrepl_bencode_read_string(data, &position)
        if key_status != .Complete {
            nrepl_request_delete(&request)
            return request, 0, key_status
        }

        if key == "line" || key == "column" {
            if position+1 < len(data) &&
               data[position] == 'l' &&
               data[position+1] == 'e' {
                position += 2
                continue
            }
            value, value_status :=
                nrepl_bencode_read_request_int(data, &position)
            if value_status != .Complete {
                nrepl_request_delete(&request)
                return request, 0, value_status
            }
            if key == "line" {
                request.line = value
                request.has_line = true
            } else {
                request.column = value
                request.has_column = true
            }
            continue
        }

        destination: ^string
        switch key {
        case "op":           destination = &request.op
        case "id":           destination = &request.id
        case "session":      destination = &request.session
        case "code":         destination = &request.code
        case "file":         destination = &request.file
        case "file-name":    destination = &request.file_name
        case "file-path":    destination = &request.file_path
        case "prefix":       destination = &request.prefix
        case "symbol":       destination = &request.symbol
        case "sym":          destination = &request.sym
        case "context":      destination = &request.completion_context
        case "ns":           destination = &request.ns
        case "interrupt-id": destination = &request.interrupt_id
        case "stdin":        destination = &request.stdin
        }
        if destination != nil {
            // Calva's encoder represents undefined optional values as i0e.
            // CIDER uses an empty list for nil. Treat both as absent for
            // optional string fields.
            if position < len(data) && data[position] == 'i' {
                absent, absent_status :=
                    nrepl_bencode_read_integer(data, &position)
                if absent_status != .Complete || absent != 0 {
                    nrepl_request_delete(&request)
                    return request, 0, .Invalid
                }
                continue
            }
            if position+1 < len(data) &&
               data[position] == 'l' &&
               data[position+1] == 'e' {
                position += 2
                continue
            }
            value, value_status :=
                nrepl_bencode_read_string(data, &position)
            if value_status != .Complete {
                nrepl_request_delete(&request)
                return request, 0, value_status
            }
            delete(destination^)
            destination^ = strings.clone(value)
            continue
        }

        value_status := nrepl_bencode_skip(data, &position, 1)
        if value_status != .Complete {
            nrepl_request_delete(&request)
            return request, 0, value_status
        }
    }
}

nrepl_bencode_write_string :: proc(builder: ^strings.Builder, value: string) {
    fmt.sbprintf(builder, "%d:", len(value))
    strings.write_string(builder, value)
}

nrepl_bencode_write_integer :: proc(builder: ^strings.Builder, value: int) {
    fmt.sbprintf(builder, "i%de", value)
}

nrepl_bencode_write_string_list :: proc(
    builder: ^strings.Builder,
    values: []string,
) {
    strings.write_byte(builder, 'l')
    for value in values {
        nrepl_bencode_write_string(builder, value)
    }
    strings.write_byte(builder, 'e')
}
