package main

import "core:bufio"
import "core:crypto"
import "core:encoding/json"
import "core:encoding/uuid"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import kvist "../../odin/kvist"

NREPL_ADAPTER_VERSION :: "0.1.0"
NREPL_DEFAULT_PORT_FILE :: ".nrepl-port"
// Kvist has no namespaces. `user` is a virtual namespace that keeps generic
// nREPL clients from trying to switch into a Clojure namespace before eval.
NREPL_NAMESPACE :: "user"
NREPL_EXCEPTION_TYPE :: "kvist.EvaluationError"

nrepl_send_mutex: sync.Mutex

Nrepl_Backend_Event :: struct {
    id:          string,
    kind:        string,
    success:     bool,
    message:     string,
    stream:      string,
    text:        string,
    worker_pid:  int,
    symbols:     []Repl_Symbol,
    diagnostics: []Repl_Diagnostic,
}

Nrepl_Backend :: struct {
    process:    os.Process,
    input:      ^os.File,
    output:     ^os.File,
    reader:     bufio.Reader,
    alive:      bool,
    next_id:    int,
    worker_pid: int,
}

Nrepl_Server :: struct {
    backend:      Nrepl_Backend,
    context_path: string,
    sessions:     [dynamic]string,
    interrupt:    ^Nrepl_Interrupt_State,
}

Nrepl_Interrupt_State :: struct {
    mutex:     sync.Mutex,
    requested: bool,
}

Nrepl_Active_Request :: struct {
    server:          ^Nrepl_Server,
    socket:          net.TCP_Socket,
    request:         Nrepl_Request,
    keep_connection: bool,
    interrupt:       Nrepl_Interrupt_State,
}

nrepl_backend_event_delete :: proc(event: ^Nrepl_Backend_Event) {
    delete(event.id)
    delete(event.kind)
    delete(event.message)
    delete(event.stream)
    delete(event.text)
    for symbol in event.symbols {
        delete(symbol.kind)
        delete(symbol.name)
        delete(symbol.detail)
        delete(symbol.signature)
        delete(symbol.doc)
        delete(symbol.file)
    }
    delete(event.symbols)
    for diagnostic in event.diagnostics {
        delete(diagnostic.severity)
        delete(diagnostic.code)
        delete(diagnostic.confidence)
        delete(diagnostic.phase)
        delete(diagnostic.message)
        delete(diagnostic.source_path)
    }
    delete(event.diagnostics)
    event^ = {}
}

nrepl_backend_read_event :: proc(
    backend: ^Nrepl_Backend,
) -> (event: Nrepl_Backend_Event, message: string, ok: bool) {
    raw, read_ok := repl_read_line(&backend.reader)
    if !read_ok {
        backend.alive = false
        return event,
               strings.clone("Kvist REPL backend closed its output"),
               false
    }
    line := repl_trim_line(raw)
    unmarshal_err := json.unmarshal(transmute([]byte)line, &event)
    delete(raw)
    if unmarshal_err != nil {
        nrepl_backend_event_delete(&event)
        return event,
               strings.clone("Kvist REPL backend returned invalid JSONL"),
               false
    }
    return event, "", true
}

nrepl_backend_start :: proc(
    context_path: string,
) -> (backend: Nrepl_Backend, message: string, ok: bool) {
    child_input, parent_input, input_err := os.pipe()
    if input_err != nil {
        return backend,
               strings.clone("failed to create Kvist REPL input pipe"),
               false
    }
    parent_output, child_output, output_err := os.pipe()
    if output_err != nil {
        _ = os.close(child_input)
        _ = os.close(parent_input)
        return backend,
               strings.clone("failed to create Kvist REPL output pipe"),
               false
    }

    process, start_err := os.process_start(os.Process_Desc{
        command = {
            os.args[0],
            "repl",
            context_path,
            "--protocol",
            "jsonl",
        },
        stdin = child_input,
        stdout = child_output,
        stderr = os.stderr,
    })
    _ = os.close(child_input)
    _ = os.close(child_output)
    if start_err != nil {
        _ = os.close(parent_input)
        _ = os.close(parent_output)
        return backend,
               strings.clone("failed to start Kvist REPL backend"),
               false
    }

    backend = Nrepl_Backend{
        process = process,
        input = parent_input,
        output = parent_output,
        alive = true,
        next_id = 1,
    }
    bufio.reader_init(&backend.reader, os.to_reader(parent_output))

    ready, ready_message, ready_ok := nrepl_backend_read_event(&backend)
    if !ready_ok || ready.kind != "ready" || !ready.success {
        if ready_ok {
            delete(ready_message)
            ready_message = strings.clone(
                ready.message if ready.message != "" else
                    "Kvist REPL backend did not become ready",
            )
        }
        nrepl_backend_event_delete(&ready)
        if backend.input != nil {
            _ = os.close(backend.input)
            backend.input = nil
        }
        _, _ = os.process_wait(backend.process)
        bufio.reader_destroy(&backend.reader)
        if backend.output != nil {
            _ = os.close(backend.output)
            backend.output = nil
        }
        backend.alive = false
        return backend, ready_message, false
    }
    backend.worker_pid = ready.worker_pid
    nrepl_backend_event_delete(&ready)
    delete(ready_message)
    return backend, "", true
}

nrepl_backend_stop :: proc(backend: ^Nrepl_Backend) {
    if !backend.alive && backend.input == nil && backend.output == nil {
        backend^ = {}
        return
    }
    if backend.input != nil {
        _ = os.close(backend.input)
    }
    _, _ = os.process_wait(backend.process)
    bufio.reader_destroy(&backend.reader)
    if backend.output != nil {
        _ = os.close(backend.output)
    }
    backend^ = {}
}

nrepl_backend_write :: proc(
    backend: ^Nrepl_Backend,
    request: Repl_Request,
) -> (message: string, ok: bool) {
    if !backend.alive {
        return strings.clone("Kvist REPL backend is not running"), false
    }
    bytes, marshal_err := json.marshal(request)
    if marshal_err != nil {
        return strings.clone("failed to encode Kvist REPL request"), false
    }
    defer delete(bytes)
    _, write_err := os.write_strings(
        backend.input,
        string(bytes),
        "\n",
    )
    if write_err != nil {
        backend.alive = false
        return fmt.aprintf(
            "failed to write to Kvist REPL backend: %v",
            write_err,
        ), false
    }
    // Pipes are unbuffered. Some platforms report ENOTSUP for flush.
    _ = os.flush(backend.input)
    return "", true
}

nrepl_backend_next_id :: proc(backend: ^Nrepl_Backend) -> string {
    id := fmt.aprintf("nrepl-%d", backend.next_id)
    backend.next_id += 1
    return id
}

nrepl_backend_reset :: proc(
    backend: ^Nrepl_Backend,
) -> (message: string, ok: bool) {
    backend_id := nrepl_backend_next_id(backend)
    defer delete(backend_id)
    write_message, wrote := nrepl_backend_write(
        backend,
        Repl_Request{id = backend_id, op = "reset"},
    )
    if !wrote {
        return write_message, false
    }
    delete(write_message)
    for {
        event, read_message, read_ok :=
            nrepl_backend_read_event(backend)
        if !read_ok {
            return read_message, false
        }
        delete(read_message)
        if event.id != backend_id && event.id != "" {
            nrepl_backend_event_delete(&event)
            continue
        }
        if event.worker_pid > 0 {
            backend.worker_pid = event.worker_pid
        }
        if event.kind == "reset" {
            successful := event.success
            reset_message := strings.clone(event.message)
            nrepl_backend_event_delete(&event)
            return reset_message, successful
        }
        nrepl_backend_event_delete(&event)
    }
}

nrepl_interrupt_requested :: proc(server: ^Nrepl_Server) -> bool {
    if server.interrupt == nil {
        return false
    }
    sync.lock(&server.interrupt.mutex)
    requested := server.interrupt.requested
    sync.unlock(&server.interrupt.mutex)
    return requested
}

nrepl_interrupt_request :: proc(state: ^Nrepl_Interrupt_State) {
    sync.lock(&state.mutex)
    state.requested = true
    sync.unlock(&state.mutex)
}

nrepl_backend_restart :: proc(
    server: ^Nrepl_Server,
) -> (message: string, ok: bool) {
    nrepl_backend_stop(&server.backend)
    backend, start_message, started :=
        nrepl_backend_start(server.context_path)
    if !started {
        server.backend = {}
        return start_message, false
    }
    server.backend = backend
    return start_message, true
}

nrepl_server_delete :: proc(server: ^Nrepl_Server) {
    nrepl_backend_stop(&server.backend)
    delete(server.context_path)
    for session in server.sessions {
        delete(session)
    }
    delete(server.sessions)
    server^ = {}
}

nrepl_server_session_index :: proc(
    server: ^Nrepl_Server,
    session: string,
) -> (index: int, found: bool) {
    for candidate, candidate_index in server.sessions {
        if candidate == session {
            return candidate_index, true
        }
    }
    return -1, false
}

nrepl_send :: proc(socket: net.TCP_Socket, payload: string) -> bool {
    sync.lock(&nrepl_send_mutex)
    defer sync.unlock(&nrepl_send_mutex)
    bytes := transmute([]byte)payload
    sent := 0
    for sent < len(bytes) {
        count, send_err := net.send_tcp(socket, bytes[sent:])
        if send_err != nil || count <= 0 {
            return false
        }
        sent += count
    }
    return true
}

nrepl_response_begin :: proc(builder: ^strings.Builder) {
    strings.write_byte(builder, 'd')
}

nrepl_response_end :: proc(builder: ^strings.Builder) {
    strings.write_byte(builder, 'e')
}

nrepl_response_field :: proc(
    builder: ^strings.Builder,
    key,
    value: string,
) {
    nrepl_bencode_write_string(builder, key)
    nrepl_bencode_write_string(builder, value)
}

nrepl_response_request_id :: proc(
    builder: ^strings.Builder,
    request: ^Nrepl_Request,
) {
    if request.id != "" {
        nrepl_response_field(builder, "id", request.id)
    }
}

nrepl_response_session :: proc(
    builder: ^strings.Builder,
    request: ^Nrepl_Request,
) {
    if request.session != "" {
        nrepl_response_field(builder, "session", request.session)
    }
}

nrepl_send_status :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    statuses: []string,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    nrepl_response_request_id(&builder, request)
    nrepl_response_session(&builder, request)
    nrepl_bencode_write_string(&builder, "status")
    nrepl_bencode_write_string_list(&builder, statuses)
    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_send_error :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    message: string,
    statuses: []string,
) -> bool {
    builder := strings.builder_make()
    nrepl_response_begin(&builder)
    nrepl_response_field(&builder, "err", message)
    nrepl_response_request_id(&builder, request)
    nrepl_response_session(&builder, request)
    nrepl_response_end(&builder)
    sent := nrepl_send(socket, strings.to_string(builder))
    strings.builder_destroy(&builder)
    if !sent {
        return false
    }
    return nrepl_send_status(socket, request, statuses)
}

nrepl_send_eval_error :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    message: string,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    if message != "" {
        nrepl_response_field(&builder, "err", message)
    }
    nrepl_response_field(&builder, "ex", NREPL_EXCEPTION_TYPE)
    nrepl_response_request_id(&builder, request)
    nrepl_response_field(&builder, "root-ex", NREPL_EXCEPTION_TYPE)
    nrepl_response_session(&builder, request)
    nrepl_bencode_write_string(&builder, "status")
    nrepl_bencode_write_string_list(
        &builder,
        {"eval-error", "done"},
    )
    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_send_stream :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    stream,
    text: string,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    if stream == "stderr" {
        nrepl_response_field(&builder, "err", text)
        nrepl_response_request_id(&builder, request)
    } else {
        nrepl_response_request_id(&builder, request)
        nrepl_response_field(&builder, "out", text)
    }
    nrepl_response_session(&builder, request)
    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_send_value :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    value: string,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    nrepl_response_request_id(&builder, request)
    nrepl_response_field(&builder, "ns", NREPL_NAMESPACE)
    nrepl_response_session(&builder, request)
    nrepl_response_field(&builder, "value", repl_trim_line(value))
    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_send_describe :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    nrepl_response_request_id(&builder, request)

    nrepl_bencode_write_string(&builder, "ops")
    strings.write_byte(&builder, 'd')
    operations := []string{
        "cider/complete",
        "cider/info",
        "clone",
        "close",
        "complete",
        "completions",
        "describe",
        "eval",
        "info",
        "interrupt",
        "load-file",
        "lookup",
        "ls-sessions",
        "ns-list",
    }
    for operation in operations {
        nrepl_bencode_write_string(&builder, operation)
        strings.write_string(&builder, "de")
    }
    strings.write_byte(&builder, 'e')

    nrepl_response_session(&builder, request)
    nrepl_bencode_write_string(&builder, "status")
    nrepl_bencode_write_string_list(&builder, {"done"})

    nrepl_bencode_write_string(&builder, "versions")
    strings.write_byte(&builder, 'd')
    nrepl_bencode_write_string(&builder, "kvist-nrepl")
    strings.write_string(&builder, "d11:incrementali0e5:majori0e5:minori1e14:version-string")
    nrepl_bencode_write_string(&builder, NREPL_ADAPTER_VERSION)
    strings.write_byte(&builder, 'e')
    nrepl_bencode_write_string(&builder, "kvist-repl")
    strings.write_string(&builder, "d11:incrementali0e5:majori1e5:minori0e14:version-string3:1.0e")
    nrepl_bencode_write_string(&builder, "nrepl")
    strings.write_string(&builder, "d11:incrementali0e5:majori1e5:minori0e14:version-string5:1.0.0e")
    strings.write_byte(&builder, 'e')

    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_send_clone :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    new_session: string,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    nrepl_response_request_id(&builder, request)
    nrepl_response_field(&builder, "new-session", new_session)
    nrepl_response_session(&builder, request)
    nrepl_bencode_write_string(&builder, "status")
    nrepl_bencode_write_string_list(&builder, {"done"})
    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_new_session_id :: proc() -> string {
    context.random_generator = crypto.random_generator()
    identifier := uuid.generate_v4()
    buffer: [36]byte
    return strings.clone(uuid.to_string(identifier, buffer[:]))
}

nrepl_send_sessions :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    sessions: []string,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    nrepl_response_request_id(&builder, request)
    nrepl_bencode_write_string(&builder, "sessions")
    nrepl_bencode_write_string_list(&builder, sessions)
    nrepl_bencode_write_string(&builder, "status")
    nrepl_bencode_write_string_list(&builder, {"done"})
    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_send_namespaces :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    nrepl_response_request_id(&builder, request)
    nrepl_bencode_write_string(&builder, "ns-list")
    nrepl_bencode_write_string_list(&builder, {NREPL_NAMESPACE})
    nrepl_response_session(&builder, request)
    nrepl_bencode_write_string(&builder, "status")
    nrepl_bencode_write_string_list(&builder, {"done"})
    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_calva_compat_value :: proc(code: string) -> (value: string, handled: bool) {
    trimmed := strings.trim_space(code)
    if trimmed == "*ns*" {
        return NREPL_NAMESPACE, true
    }
    // Calva evaluates this Clojure-only form after every CLJ connection. Its
    // WebSocket transport treats the same probe as a successful no-op.
    if strings.contains(trimmed, "clojure.main/repl-requires") {
        return "nil", true
    }
    // Calva checks these JVM properties before sending interrupt. Kvist has no
    // JVM, so both probes intentionally report no value.
    if trimmed == `(System/getProperty "java.version")` ||
       trimmed == `(System/getProperty "jdk.attach.allowAttachSelf")` {
        return "nil", true
    }
    // Conjure classifies sessions with a reader-conditional and installs a
    // Clojure-only helper preamble. Neither changes Kvist runtime state.
    if strings.has_prefix(trimmed, "#?(") &&
       strings.contains(trimmed, ":default 'unknown") {
        return "unknown", true
    }
    if strings.contains(trimmed, "create-ns 'conjure.internal") &&
       strings.contains(trimmed, "bounded-conj") {
        return "nil", true
    }
    // Generic nREPL clients commonly establish their logical namespace before
    // the first eval. Kvist has no namespaces, so retain the virtual `user` ns.
    if strings.has_prefix(trimmed, "(ns ") &&
       strings.has_suffix(trimmed, ")") {
        return NREPL_NAMESPACE, true
    }
    return "", false
}

nrepl_send_compat_eval :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    value: string,
) -> bool {
    if !nrepl_send_value(socket, request, value) {
        return false
    }
    return nrepl_send_status(socket, request, {"done"})
}

nrepl_send_validated_compat_eval :: proc(
    server: ^Nrepl_Server,
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    value: string,
) -> bool {
    if !nrepl_request_session_valid(server, request) {
        return nrepl_send_status(
            socket,
            request,
            {"unknown-session", "done"},
        )
    }
    return nrepl_send_compat_eval(socket, request, value)
}

nrepl_diagnostic_text :: proc(diagnostic: Repl_Diagnostic) -> string {
    path := diagnostic.source_path
    if path == "" {
        path = "<eval>"
    }
    severity := diagnostic.severity
    if severity == "" {
        severity = "error"
    }
    return fmt.aprintf(
        "%s:%d:%d: %s: %s\n",
        path,
        max(diagnostic.line, 1),
        max(diagnostic.column, 1),
        severity,
        diagnostic.message,
    )
}

nrepl_forward_eval :: proc(
    server: ^Nrepl_Server,
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    source,
    source_path: string,
) -> bool {
    if nrepl_interrupt_requested(server) {
        return nrepl_send_status(
            socket,
            request,
            {"interrupted", "done"},
        )
    }
    backend_id := nrepl_backend_next_id(&server.backend)
    defer delete(backend_id)
    backend_request := Repl_Request{
        id = backend_id,
        op = "eval",
        source = source,
        source_path = source_path,
        line = Repl_Optional_Int(request.line) if request.has_line else {},
        column = Repl_Optional_Int(request.column) if request.has_column else {},
    }
    write_message, wrote := nrepl_backend_write(
        &server.backend,
        backend_request,
    )
    if !wrote {
        defer delete(write_message)
        if nrepl_interrupt_requested(server) {
            return nrepl_send_status(
                socket,
                request,
                {"interrupted", "done"},
            )
        }
        return nrepl_send_eval_error(socket, request, write_message)
    }
    delete(write_message)

    emitted_error := false
    for {
        event, read_message, read_ok :=
            nrepl_backend_read_event(&server.backend)
        if !read_ok {
            defer delete(read_message)
            if nrepl_interrupt_requested(server) {
                return nrepl_send_status(
                    socket,
                    request,
                    {"interrupted", "done"},
                )
            }
            return nrepl_send_eval_error(socket, request, read_message)
        }
        delete(read_message)
        if event.id != backend_id && event.id != "" {
            nrepl_backend_event_delete(&event)
            continue
        }
        if event.worker_pid > 0 {
            server.backend.worker_pid = event.worker_pid
        }

        sent := true
        switch event.kind {
        case "stream-output":
            sent = nrepl_send_stream(
                socket,
                request,
                event.stream,
                event.text,
            )
        case "output":
            if event.stream == "stderr" {
                emitted_error = true
                sent = nrepl_send_stream(
                    socket,
                    request,
                    "stderr",
                    event.text,
                )
            } else {
                sent = nrepl_send_value(socket, request, event.text)
            }
        case "result":
            sent = nrepl_send_value(socket, request, event.text)
        case "diagnostics":
            for diagnostic in event.diagnostics {
                diagnostic_text := nrepl_diagnostic_text(diagnostic)
                sent = nrepl_send_stream(
                    socket,
                    request,
                    "stderr",
                    diagnostic_text,
                )
                delete(diagnostic_text)
                emitted_error = true
                if !sent {
                    break
                }
            }
        case "complete":
            if !event.success && !emitted_error && event.message != "" {
                sent = nrepl_send_stream(
                    socket,
                    request,
                    "stderr",
                    event.message,
                )
            }
            success := event.success
            nrepl_backend_event_delete(&event)
            if !sent {
                return false
            }
            if success {
                return nrepl_send_status(socket, request, {"done"})
            }
            if nrepl_interrupt_requested(server) {
                return nrepl_send_status(
                    socket,
                    request,
                    {"interrupted", "done"},
                )
            }
            return nrepl_send_eval_error(socket, request, "")
        }
        nrepl_backend_event_delete(&event)
        if !sent {
            return false
        }
    }
}

nrepl_send_completions :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    symbols: []Repl_Symbol,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    nrepl_bencode_write_string(&builder, "completions")
    strings.write_byte(&builder, 'l')
    for symbol in symbols {
        strings.write_byte(&builder, 'd')
        nrepl_response_field(&builder, "candidate", symbol.name)
        nrepl_response_field(&builder, "ns", NREPL_NAMESPACE)
        nrepl_response_field(
            &builder,
            "type",
            nrepl_symbol_type(symbol),
        )
        strings.write_byte(&builder, 'e')
    }
    strings.write_byte(&builder, 'e')
    nrepl_response_request_id(&builder, request)
    nrepl_response_session(&builder, request)
    nrepl_bencode_write_string(&builder, "status")
    nrepl_bencode_write_string_list(&builder, {"done"})
    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_symbol_type :: proc(symbol: Repl_Symbol) -> string {
    switch symbol.kind {
    case "macro", "transform":
        return "macro"
    case "type", "struct", "enum", "union":
        return "class"
    case "proc", "defn", "defn-", "function", "iterator":
        return "function"
    }
    if symbol.signature != "" {
        return "function"
    }
    return "var"
}

nrepl_file_uri :: proc(path: string) -> string {
    if strings.contains(path, "://") || strings.has_prefix(path, "file:") {
        return strings.clone(path)
    }
    resolved := path
    owned_resolved := ""
    defer delete(owned_resolved)
    if path != "" && !os.is_absolute_path(path) {
        if absolute, absolute_err :=
            os.get_absolute_path(path, context.allocator); absolute_err == nil {
            resolved = absolute
            owned_resolved = absolute
        }
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "file://")
    if len(resolved) == 0 || (resolved[0] != '/' && resolved[0] != '\\') {
        strings.write_byte(&builder, '/')
    }
    for value in transmute([]byte)resolved {
        switch value {
        case 'A'..='Z', 'a'..='z', '0'..='9', '-', '_', '.', '~', '/', ':':
            strings.write_byte(&builder, value)
        case '\\':
            strings.write_byte(&builder, '/')
        case:
            fmt.sbprintf(&builder, "%%%02X", value)
        }
    }
    return strings.clone(strings.to_string(builder))
}

nrepl_send_lookup :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    symbol: ^Repl_Symbol,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    nrepl_response_request_id(&builder, request)
    nrepl_bencode_write_string(&builder, "info")
    strings.write_byte(&builder, 'd')
    if symbol != nil {
        if symbol.signature != "" {
            nrepl_response_field(
                &builder,
                "arglists-str",
                symbol.signature,
            )
        }
        nrepl_bencode_write_string(&builder, "column")
        nrepl_bencode_write_integer(&builder, symbol.column)
        if symbol.doc != "" {
            nrepl_response_field(&builder, "doc", symbol.doc)
        }
        if symbol.file != "" {
            file_uri := nrepl_file_uri(symbol.file)
            nrepl_response_field(&builder, "file", file_uri)
            delete(file_uri)
        }
        nrepl_bencode_write_string(&builder, "line")
        nrepl_bencode_write_integer(&builder, symbol.line)
        nrepl_response_field(&builder, "name", symbol.name)
        nrepl_response_field(
            &builder,
            "type",
            nrepl_symbol_type(symbol^),
        )
    }
    strings.write_byte(&builder, 'e')
    nrepl_response_session(&builder, request)
    nrepl_bencode_write_string(&builder, "status")
    nrepl_bencode_write_string_list(&builder, {"done"})
    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_send_info :: proc(
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
    symbol: ^Repl_Symbol,
) -> bool {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    nrepl_response_begin(&builder)
    if symbol != nil && symbol.signature != "" {
        nrepl_response_field(
            &builder,
            "arglists-str",
            symbol.signature,
        )
    }
    if symbol != nil {
        nrepl_bencode_write_string(&builder, "column")
        nrepl_bencode_write_integer(&builder, symbol.column)
        if symbol.doc != "" {
            nrepl_response_field(&builder, "doc", symbol.doc)
        }
        if symbol.file != "" {
            file_uri := nrepl_file_uri(symbol.file)
            nrepl_response_field(&builder, "file", file_uri)
            delete(file_uri)
        }
    }
    nrepl_response_request_id(&builder, request)
    if symbol != nil {
        nrepl_bencode_write_string(&builder, "line")
        nrepl_bencode_write_integer(&builder, symbol.line)
        nrepl_response_field(&builder, "name", symbol.name)
    }
    nrepl_response_session(&builder, request)
    nrepl_bencode_write_string(&builder, "status")
    if symbol == nil {
        nrepl_bencode_write_string_list(
            &builder,
            {"no-info", "done"},
        )
    } else {
        nrepl_bencode_write_string_list(&builder, {"done"})
        nrepl_response_field(
            &builder,
            "type",
            nrepl_symbol_type(symbol^),
        )
    }
    nrepl_response_end(&builder)
    return nrepl_send(socket, strings.to_string(builder))
}

nrepl_forward_tooling :: proc(
    server: ^Nrepl_Server,
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
) -> bool {
    backend_id := nrepl_backend_next_id(&server.backend)
    defer delete(backend_id)
    completion := request.op == "completions" ||
                  request.op == "complete" ||
                  request.op == "cider/complete"
    name := request.symbol
    if name == "" {
        name = request.prefix if completion else request.sym
    }
    tooling_source := request.completion_context
    if tooling_source == "" {
        tooling_source = request.code
    }
    source_path := request.file
    if source_path == "" {
        source_path = request.file_path
    }
    backend_request := Repl_Request{
        id = backend_id,
        op = "complete" if completion else "lookup",
        name = name,
        source = tooling_source,
        source_path = source_path,
        line = Repl_Optional_Int(request.line) if request.has_line else {},
        column = Repl_Optional_Int(request.column) if request.has_column else {},
    }
    write_message, wrote := nrepl_backend_write(
        &server.backend,
        backend_request,
    )
    if !wrote {
        defer delete(write_message)
        return nrepl_send_error(
            socket,
            request,
            write_message,
            {"error", "done"},
        )
    }
    delete(write_message)

    symbols: [dynamic]Repl_Symbol
    defer delete(symbols)
    successful := false
    completion_message := ""
    defer delete(completion_message)
    for {
        event, read_message, read_ok :=
            nrepl_backend_read_event(&server.backend)
        if !read_ok {
            defer delete(read_message)
            return nrepl_send_error(
                socket,
                request,
                read_message,
                {"error", "done"},
            )
        }
        delete(read_message)
        if event.id != backend_id && event.id != "" {
            nrepl_backend_event_delete(&event)
            continue
        }
        if event.kind == "completions" || event.kind == "lookup" {
            for symbol in event.symbols {
                append(&symbols, symbol)
            }
            delete(event.symbols)
            event.symbols = nil
        }
        if event.kind == "complete" {
            successful = event.success
            completion_message = strings.clone(event.message)
            nrepl_backend_event_delete(&event)
            break
        }
        nrepl_backend_event_delete(&event)
    }

    defer for symbol in symbols {
        delete(symbol.kind)
        delete(symbol.name)
        delete(symbol.detail)
        delete(symbol.signature)
        delete(symbol.doc)
        delete(symbol.file)
    }
    if !successful {
        return nrepl_send_error(
            socket,
            request,
            completion_message,
            {"error", "done"},
        )
    }
    if completion {
        return nrepl_send_completions(
            socket,
            request,
            symbols[:],
        )
    }
    symbol: ^Repl_Symbol
    if len(symbols) > 0 {
        symbol = &symbols[0]
    }
    if request.op == "info" || request.op == "cider/info" {
        return nrepl_send_info(socket, request, symbol)
    }
    return nrepl_send_lookup(socket, request, symbol)
}

nrepl_load_file_source :: proc(
    source,
    source_path: string,
) -> (prepared: string, message: string, ok: bool) {
    forms, compile_err, parsed := kvist.read_top_forms(source, source_path)
    if !parsed {
        message = kvist.format_compile_error(source_path, source, compile_err)
        return "", message, false
    }
    defer kvist.delete_borrowed_cst_top_form_slice(&forms)

    bytes := make([]byte, len(source))
    defer delete(bytes)
    copy(bytes, transmute([]byte)source)
    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) == 0 ||
           form.items[0].kind != .Symbol {
            continue
        }
        head := form.items[0].text
        skip := head == "package" || head == "comment"
        if (head == "defn" || head == "defn-") &&
           len(form.items) > 1 &&
           form.items[1].kind == .Symbol &&
           form.items[1].text == "main" {
            skip = true
        }
        if !skip {
            continue
        }
        start := max(form.span.start, 0)
        end := min(form.span.end, len(bytes))
        for i in start ..< end {
            if bytes[i] != '\n' && bytes[i] != '\r' {
                bytes[i] = ' '
            }
        }
    }
    return strings.clone(string(bytes)), "", true
}

nrepl_request_source_path :: proc(request: ^Nrepl_Request) -> string {
    if request.file_path != "" {
        return request.file_path
    }
    if request.file_name != "" {
        return request.file_name
    }
    return "<nrepl-load-file>"
}

nrepl_request_session_valid :: proc(
    server: ^Nrepl_Server,
    request: ^Nrepl_Request,
) -> bool {
    if request.session == "" {
        return true
    }
    _, found := nrepl_server_session_index(server, request.session)
    return found
}

nrepl_handle_request :: proc(
    server: ^Nrepl_Server,
    socket: net.TCP_Socket,
    request: ^Nrepl_Request,
) -> bool {
    switch request.op {
    case "describe":
        return nrepl_send_describe(socket, request)
    case "ls-sessions":
        return nrepl_send_sessions(socket, request, server.sessions[:])
    case "ns-list":
        return nrepl_send_namespaces(socket, request)
    case "clone":
        if !nrepl_request_session_valid(server, request) {
            return nrepl_send_status(
                socket,
                request,
                {"unknown-session", "done"},
            )
        }
        new_session := nrepl_new_session_id()
        append(&server.sessions, new_session)
        return nrepl_send_clone(socket, request, new_session)
    case "close":
        index, found :=
            nrepl_server_session_index(server, request.session)
        if !found {
            return nrepl_send_status(
                socket,
                request,
                {"unknown-session", "done"},
            )
        }
        delete(server.sessions[index])
        ordered_remove(&server.sessions, index)
        return nrepl_send_status(
            socket,
            request,
            {"session-closed", "done"},
        )
    }

    if !nrepl_request_session_valid(server, request) {
        return nrepl_send_status(
            socket,
            request,
            {"unknown-session", "done"},
        )
    }

    switch request.op {
    case "eval":
        if value, handled := nrepl_calva_compat_value(request.code); handled {
            return nrepl_send_compat_eval(socket, request, value)
        }
        return nrepl_forward_eval(
            server,
            socket,
            request,
            request.code,
            request.file,
        )
    case "load-file":
        source_path := nrepl_request_source_path(request)
        prepared, prepare_message, prepared_ok :=
            nrepl_load_file_source(request.file, source_path)
        if !prepared_ok {
            defer delete(prepare_message)
            if nrepl_interrupt_requested(server) {
                return nrepl_send_status(
                    socket,
                    request,
                    {"interrupted", "done"},
                )
            }
            return nrepl_send_eval_error(
                socket,
                request,
                prepare_message,
            )
        }
        defer delete(prepared)
        delete(prepare_message)
        return nrepl_forward_eval(
            server,
            socket,
            request,
            prepared,
            source_path,
        )
    case "completions", "complete", "cider/complete",
         "lookup", "info", "cider/info":
        return nrepl_forward_tooling(server, socket, request)
    case "stdin":
        return nrepl_send_status(
            socket,
            request,
            {"stdin-not-supported", "done"},
        )
    }
    return nrepl_send_status(
        socket,
        request,
        {"unknown-op", "done"},
    )
}

nrepl_active_request_run :: proc(data: rawptr) {
    active := cast(^Nrepl_Active_Request)data
    active.keep_connection = nrepl_handle_request(
        active.server,
        active.socket,
        &active.request,
    )
}

nrepl_active_request_finish :: proc(
    server: ^Nrepl_Server,
    active: ^Nrepl_Active_Request,
    active_thread: ^^thread.Thread,
) -> bool {
    if active_thread^ == nil {
        return true
    }
    thread.join(active_thread^)
    thread.destroy(active_thread^)
    active_thread^ = nil
    keep_connection := active.keep_connection
    nrepl_request_delete(&active.request)
    server.interrupt = nil
    active^ = {}
    return keep_connection
}

nrepl_active_request_interrupt :: proc(
    server: ^Nrepl_Server,
    active: ^Nrepl_Active_Request,
    active_thread: ^^thread.Thread,
) -> (message: string, ok: bool) {
    if server.backend.worker_pid <= 0 {
        return strings.clone(
            "Kvist REPL backend did not report an interruptible worker",
        ), false
    }
    worker_process, open_err :=
        os.process_open(server.backend.worker_pid)
    if open_err != nil {
        return strings.clone(
            "failed to open the active Kvist REPL worker",
        ), false
    }
    nrepl_interrupt_request(&active.interrupt)
    kill_err := os.process_kill(worker_process)
    if kill_err != nil {
        _, _ = os.process_wait(worker_process, 0)
        return strings.clone(
            "failed to terminate the active Kvist REPL worker",
        ), false
    }
    _ = nrepl_active_request_finish(
        server,
        active,
        active_thread,
    )
    _, _ = os.process_wait(worker_process, 0)
    server.backend.worker_pid = 0

    reset_message, reset_ok := nrepl_backend_reset(&server.backend)
    if reset_ok {
        return reset_message, true
    }
    delete(reset_message)
    return nrepl_backend_restart(server)
}

nrepl_serve_connection :: proc(
    server: ^Nrepl_Server,
    socket: net.TCP_Socket,
) {
    buffer: [dynamic]byte
    defer delete(buffer)
    received: [8192]byte
    active := Nrepl_Active_Request{}
    active_thread: ^thread.Thread
    defer {
        if active_thread != nil {
            if !thread.is_done(active_thread) {
                restart_message, _ := nrepl_active_request_interrupt(
                    server,
                    &active,
                    &active_thread,
                )
                delete(restart_message)
            } else {
                _ = nrepl_active_request_finish(
                    server,
                    &active,
                    &active_thread,
                )
            }
        }
    }
    for {
        count, recv_err := net.recv_tcp(socket, received[:])
        if recv_err != nil || count == 0 {
            return
        }
        if len(buffer)+count > NREPL_MAX_MESSAGE_BYTES {
            return
        }
        append(&buffer, ..received[:count])
        for len(buffer) > 0 {
            request, consumed, status :=
                nrepl_bencode_decode_request(buffer[:])
            if status == .Incomplete {
                break
            }
            if status == .Invalid {
                nrepl_request_delete(&request)
                return
            }
            if active_thread != nil && thread.is_done(active_thread) {
                if !nrepl_active_request_finish(
                    server,
                    &active,
                    &active_thread,
                ) {
                    nrepl_request_delete(&request)
                    return
                }
            }

            keep_connection := true
            if request.op == "interrupt" {
                if !nrepl_request_session_valid(server, &request) {
                    keep_connection = nrepl_send_status(
                        socket,
                        &request,
                        {"unknown-session", "done"},
                    )
                } else if active_thread == nil ||
                          (request.session != "" &&
                           request.session != active.request.session) {
                    keep_connection = nrepl_send_status(
                        socket,
                        &request,
                        {"session-idle", "done"},
                    )
                } else if request.interrupt_id != "" &&
                          request.interrupt_id != active.request.id {
                    keep_connection = nrepl_send_status(
                        socket,
                        &request,
                        {"interrupt-id-mismatch", "done"},
                    )
                } else {
                    restart_message, restarted :=
                        nrepl_active_request_interrupt(
                            server,
                            &active,
                            &active_thread,
                        )
                    if restarted {
                        keep_connection = nrepl_send_status(
                            socket,
                            &request,
                            {"interrupted", "done"},
                        )
                    } else {
                        keep_connection = nrepl_send_error(
                            socket,
                            &request,
                            restart_message,
                            {"interrupted", "server-error", "done"},
                        )
                    }
                    delete(restart_message)
                }
            } else if active_thread != nil {
                if value, handled :=
                    nrepl_calva_compat_value(request.code);
                   request.op == "eval" && handled {
                    keep_connection = nrepl_send_validated_compat_eval(
                        server,
                        socket,
                        &request,
                        value,
                    )
                } else {
                    keep_connection = nrepl_send_status(
                        socket,
                        &request,
                        {"server-busy", "done"},
                    )
                }
            } else if value, handled :=
                nrepl_calva_compat_value(request.code);
               request.op == "eval" && handled {
                // Compatibility probes do not touch backend state. Answering
                // them inline also avoids a short busy window between an
                // interrupt and Conjure's session-type probe.
                keep_connection = nrepl_send_validated_compat_eval(
                    server,
                    socket,
                    &request,
                    value,
                )
            } else if request.op == "eval" || request.op == "load-file" {
                active = Nrepl_Active_Request{
                    server = server,
                    socket = socket,
                    request = request,
                    keep_connection = true,
                }
                request = {}
                server.interrupt = &active.interrupt
                active_thread = thread.create_and_start_with_data(
                    rawptr(&active),
                    nrepl_active_request_run,
                )
            } else {
                keep_connection =
                    nrepl_handle_request(server, socket, &request)
            }
            nrepl_request_delete(&request)
            if !keep_connection {
                return
            }
            remaining := len(buffer)-consumed
            if remaining > 0 {
                copy(buffer[:remaining], buffer[consumed:])
            }
            resize(&buffer, remaining)
        }
    }
}

nrepl_remove_owned_port_file :: proc(path, expected: string) {
    if path == "" {
        return
    }
    bytes, read_err :=
        os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return
    }
    matches := strings.trim_space(string(bytes)) == expected
    delete(bytes)
    if matches {
        _ = os.remove(path)
    }
}

nrepl_command :: proc(
    context_path: string,
    port: int,
    port_file: string,
    once: bool,
) -> int {
    backend, backend_message, backend_ok :=
        nrepl_backend_start(context_path)
    if !backend_ok {
        fmt.eprintln(backend_message)
        delete(backend_message)
        return 1
    }
    delete(backend_message)
    server := Nrepl_Server{
        backend = backend,
        context_path = strings.clone(context_path),
    }
    defer nrepl_server_delete(&server)

    listener, listen_err := net.listen_tcp(net.Endpoint{
        address = net.IP4_Loopback,
        port = port,
    })
    if listen_err != nil {
        fmt.eprintln("could not listen for nREPL connections")
        return 1
    }
    defer net.close(listener)
    endpoint, endpoint_err := net.bound_endpoint(listener)
    if endpoint_err != nil {
        fmt.eprintln("could not determine nREPL port")
        return 1
    }
    port_text := fmt.aprintf("%d", endpoint.port)
    defer delete(port_text)
    if port_file != "" {
        if os.write_entire_file_from_string(port_file, port_text) != nil {
            fmt.eprintf("could not write nREPL port file: %s\n", port_file)
            return 1
        }
    }
    defer nrepl_remove_owned_port_file(port_file, port_text)
    fmt.printf("Kvist nREPL listening on 127.0.0.1:%d\n", endpoint.port)
    _ = os.flush(os.stdout)

    for {
        client, _, accept_err := net.accept_tcp(listener)
        if accept_err != nil {
            fmt.eprintln("failed to accept nREPL connection")
            return 1
        }
        nrepl_serve_connection(&server, client)
        net.close(client)
        if once {
            return 0
        }
    }
}

parse_nrepl_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }
    context_path := os.args[2]
    port := 0
    port_file := NREPL_DEFAULT_PORT_FILE
    once := false
    i := 3
    for i < len(os.args) {
        switch os.args[i] {
        case "--port":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            parsed_port, parsed := strconv.parse_int(os.args[i+1])
            if !parsed || parsed_port < 0 || parsed_port > 65535 {
                fmt.eprintln("--port must be between 0 and 65535")
                exit_with_timing(2)
            }
            port = parsed_port
            i += 2
        case "--port-file":
            if i+1 >= len(os.args) || os.args[i+1] == "" {
                print_usage()
                exit_with_timing(2)
            }
            port_file = os.args[i+1]
            i += 2
        case "--no-port-file":
            port_file = ""
            i += 1
        case "--once":
            once = true
            i += 1
        case:
            print_usage()
            exit_with_timing(2)
        }
    }
    exit_with_timing(
        nrepl_command(context_path, port, port_file, once),
    )
}
