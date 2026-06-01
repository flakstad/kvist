package http

import "base:intrinsics"
import "core:log"
import nbio "core:nbio"
import mpsc "internal/mpsc"

mark_async :: proc(h: ^Handler, res: ^Response, work_data: rawptr = rawptr(uintptr(1))) {
	if res == nil || res._conn == nil || res._conn.owning_thread == nil {
		log.error("mark_async: invalid response or connection state")
		return
	}

	if atomic_load(&res._conn.server.closing) {
		log.warn("mark_async: server is closing, ignoring")
		return
	}

	if h != nil {
		res.async_handler = h
	} else if res.async_handler == nil {
		assert(false, "mark_async: h is nil and res.async_handler not set. Always pass h in middleware.")
		res.async_handler = &res._conn.server.handler
	}

	res.work_data = work_data
	intrinsics.atomic_add(&res._conn.owning_thread.async_pending, 1)
}

cancel_async :: proc(res: ^Response) {
	if res == nil || res._conn == nil || res._conn.owning_thread == nil {
		log.error("cancel_async: invalid response or connection state")
		return
	}

	if res.work_data == nil {
		log.error("cancel_async: response is not async, nothing to undo")
		return
	}

	intrinsics.atomic_add(&res._conn.owning_thread.async_pending, -1)
	res.work_data = nil
	res.async_handler = nil
}

resume :: proc(res: ^Response) {
	if res == nil || res._conn == nil || res._conn.owning_thread == nil {
		log.error("resume: invalid response or connection state")
		return
	}

	td := res._conn.owning_thread
	msg: Maybe(^Response) = res
	if mpsc.push(&td.resume_queue, &msg) {
		nbio.wake_up(td.event_loop)
	}
}
