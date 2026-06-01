package http

import "core:bytes"
import "core:container/queue"
import "core:log"
import "core:mem"
import "core:nbio"
import "core:net"
import "core:strings"

Sse :: struct {
	user_data: rawptr,
	on_err:    Maybe(Sse_On_Error),
	r:         ^Response,
	state:     Sse_State,
	_events:   queue.Queue(Sse_Event),
	_buf:      strings.Builder,
	_sent:     int,
	timeout_op: ^nbio.Operation,
	allocator: mem.Allocator,
}

Sse_Event :: struct {
	event:   Maybe(string),
	data:    Maybe(string),
	id:      Maybe(string),
	retry:   Maybe(int),
	comment: Maybe(string),
}

Sse_State :: enum {
	Pre_Start,
	Starting,
	Idle,
	Sending,
	Ending,
	Close,
}

Sse_On_Error :: #type proc(sse: ^Sse, err: net.Send_Error)

sse_init :: proc(
	sse: ^Sse,
	r: ^Response,
	user_data: rawptr = nil,
	on_error: Maybe(Sse_On_Error) = nil,
	allocator := context.temp_allocator,
) {
	sse.r = r
	sse.user_data = user_data
	sse.on_err = on_error
	sse.allocator = allocator

	queue.init(&sse._events, allocator = allocator)
	strings.builder_init(&sse._buf, allocator)

	if r.status == .Not_Found do r.status = .OK
	if !headers_has_unsafe(r.headers, "content-type") {
		headers_set_unsafe(&r.headers, "content-type", "text/event-stream")
	}
	if !headers_has_unsafe(r.headers, "cache-control") {
		headers_set_unsafe(&r.headers, "cache-control", "no-cache")
	}
	if !headers_has_unsafe(r.headers, "connection") {
		headers_set_unsafe(&r.headers, "connection", "keep-alive")
	}
}

sse_start :: proc(sse: ^Sse) {
	sse.state = .Starting
	_response_write_heading(sse.r, -1)

	on_start_send :: proc(op: ^nbio.Operation, sse: ^Sse) {
		if op.send.err != nil {
			_sse_err(sse, op.send.err)
			return
		}

		_sse_process(sse)
	}

	buf := bytes.buffer_to_bytes(&sse.r._buf)
	nbio.send_poly(sse.r._conn.socket, {buf}, sse, on_start_send, l = sse.r._conn.owning_thread.event_loop)
}

sse_event :: proc(sse: ^Sse, ev: Sse_Event, loc := #caller_location) {
	assert_has_td(loc)

	switch sse.state {
	case .Starting, .Sending, .Ending, .Idle:
		queue.push_back(&sse._events, _sse_event_clone(ev, sse.allocator))
	case .Pre_Start:
		panic("sse_start must be called first", loc)
	case .Close:
	}

	if sse.state == .Idle {
		_sse_process(sse)
	}
}

sse_end_force :: proc(sse: ^Sse) {
	sse.state = .Close

	_sse_call_on_err(sse, nil)
	sse_destroy(sse)
	connection_close(sse.r._conn)
}

sse_end :: proc(sse: ^Sse) {
	if sse.state >= .Ending do return

	if sse.state == .Sending {
		sse.state = .Ending
		return
	}

	sse.state = .Close

	_sse_call_on_err(sse, nil)
	sse_destroy(sse)
	connection_close(sse.r._conn)
}

sse_destroy :: proc(sse: ^Sse) {
	if sse.timeout_op != nil {
		nbio.remove(sse.timeout_op)
		sse.timeout_op = nil
	}
	for queue.len(sse._events) > 0 {
		ev := queue.front_ptr(&sse._events)
		_sse_event_destroy(ev, sse.allocator)
		queue.pop_front(&sse._events)
	}
	strings.builder_destroy(&sse._buf)
	queue.destroy(&sse._events)
}

_sse_err :: proc(sse: ^Sse, err: net.Send_Error) {
	if sse.state >= .Ending do return

	sse.state = .Close

	_sse_call_on_err(sse, err)
	sse_destroy(sse)
	connection_close(sse.r._conn)
}

_sse_call_on_err :: proc(sse: ^Sse, err: net.Send_Error) {
	if cb, ok := sse.on_err.?; ok {
		cb(sse, err)
	} else if err != nil {
		log.infof("Server Sent Event error: %v", err)
	}
}

_sse_process :: proc(sse: ^Sse) {
	if sse.state == .Close do return

	if queue.len(sse._events) == 0 {
		#partial switch sse.state {
		case .Ending:
			sse_end_force(sse)
		case:
			sse.state = .Idle
		}
		return
	}

	#partial switch sse.state {
	case .Ending:
	case:
		sse.state = .Sending
	}

	_sse_event_prepare(sse)
	nbio.send_poly(sse.r._conn.socket, {sse._buf.buf[:]}, sse, _sse_on_send, l = sse.r._conn.owning_thread.event_loop)
}

_sse_on_send :: proc(op: ^nbio.Operation, sse: ^Sse) {
	if op.send.err != nil {
		_sse_err(sse, op.send.err)
		return
	}

	if sse.state == .Close do return

	ev := queue.front_ptr(&sse._events)
	_sse_event_destroy(ev, sse.allocator)
	queue.pop_front(&sse._events)
	_sse_process(sse)
}

_sse_write_multiline_data :: proc(b: ^strings.Builder, prefix, text: string) {
	start := 0
	for {
		newline := strings.index(text[start:], "\n")
		if newline < 0 {
			strings.write_string(b, prefix)
			if len(text[start:]) > 0 {
				strings.write_string(b, text[start:])
			}
			strings.write_string(b, "\r\n")
			break
		}

		line := text[start:start+newline]
		strings.write_string(b, prefix)
		if len(line) > 0 {
			strings.write_string(b, line)
		}
		strings.write_string(b, "\r\n")
		start += newline + 1
		if start > len(text) {
			break
		}
	}
}

_sse_event_prepare :: proc(sse: ^Sse) {
	ev := queue.front_ptr(&sse._events)^
	b := &sse._buf

	strings.builder_reset(b)
	sse._sent = 0

	if name, ok := ev.event.?; ok {
		strings.write_string(b, "event: ")
		strings.write_string(b, name)
		strings.write_string(b, "\r\n")
	}

	if cmnt, ok := ev.comment.?; ok {
		strings.write_string(b, ": ")
		strings.write_string(b, cmnt)
		strings.write_string(b, "\r\n")
	}

	if id, ok := ev.id.?; ok {
		strings.write_string(b, "id: ")
		strings.write_string(b, id)
		strings.write_string(b, "\r\n")
	}

	if retry, ok := ev.retry.?; ok {
		strings.write_string(b, "retry: ")
		strings.write_int(b, retry)
		strings.write_string(b, "\r\n")
	}

	if data, ok := ev.data.?; ok {
		_sse_write_multiline_data(b, "data: ", data)
	}

	strings.write_string(b, "\r\n")
}

_sse_clone_maybe_string :: proc(text: Maybe(string), allocator: mem.Allocator) -> Maybe(string) {
	if s, ok := text.?; ok {
		return strings.clone(s, allocator)
	}
	return nil
}

_sse_event_clone :: proc(ev: Sse_Event, allocator: mem.Allocator) -> Sse_Event {
	return Sse_Event{
		event   = _sse_clone_maybe_string(ev.event, allocator),
		data    = _sse_clone_maybe_string(ev.data, allocator),
		id      = _sse_clone_maybe_string(ev.id, allocator),
		retry   = ev.retry,
		comment = _sse_clone_maybe_string(ev.comment, allocator),
	}
}

_sse_destroy_maybe_string :: proc(text: ^Maybe(string), allocator: mem.Allocator) {
	if s, ok := text^.?; ok {
		delete(s, allocator)
		text^ = nil
	}
}

_sse_event_destroy :: proc(ev: ^Sse_Event, allocator: mem.Allocator) {
	_sse_destroy_maybe_string(&ev.event, allocator)
	_sse_destroy_maybe_string(&ev.data, allocator)
	_sse_destroy_maybe_string(&ev.id, allocator)
	_sse_destroy_maybe_string(&ev.comment, allocator)
}
