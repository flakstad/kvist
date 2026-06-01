package main

import "core:mem"
import "core:nbio"
import "core:net"
import "core:time"

import http "../vendor/odin-http"

JSON_STATIC: string : "{\"message\":\"pong\",\"count\":1,\"ok\":true,\"service\":\"odin-http\",\"env\":\"bench\",\"user\":\"load-test\",\"stats\":{\"latency_ms\":12,\"cpu_pct\":37,\"mem_mb\":128},\"meta\":{\"request_id\":\"req-123456789\",\"build\":\"2026.06.01\",\"region\":\"eu-north-1\"},\"note\":\"Longer JSON payload for rough comparison.\"}"

Json_Stats :: struct {
	latency_ms: int,
	cpu_pct:    int,
	mem_mb:     int,
}

Json_Meta :: struct {
	request_id: string,
	build:      string,
	region:     string,
}

Json_Reply :: struct {
	message: string,
	count:   int,
	ok:      bool,
	service: string,
	env:     string,
	user:    string,
	stats:   Json_Stats,
	meta:    Json_Meta,
	note:    string,
}

json_reply :: Json_Reply{
	message = "pong",
	count   = 1,
	ok      = true,
	service = "odin-http",
	env     = "bench",
	user    = "load-test",
	stats   = Json_Stats{latency_ms = 12, cpu_pct = 37, mem_mb = 128},
	meta    = Json_Meta{request_id = "req-123456789", build = "2026.06.01", region = "eu-north-1"},
	note    = "Longer JSON payload for rough comparison.",
}

schedule_tick :: proc(stream: ^http.Sse) {
	if stream == nil || stream.state > .Ending {
		return
	}
	if stream.timeout_op != nil {
		nbio.remove(stream.timeout_op)
		stream.timeout_op = nil
	}
	on_sse_timeout :: proc(op: ^nbio.Operation, stream: ^http.Sse) {
		stream.timeout_op = nil
		if stream.state > .Ending {
			return
		}
		http.sse_event(stream, http.Sse_Event{event = "tick", data = "ok"})
		schedule_tick(stream)
	}
	stream.timeout_op = nbio.timeout_poly(time.Second, stream, on_sse_timeout, l = stream.r._conn.owning_thread.event_loop)
}

on_sse_error :: proc(stream: ^http.Sse, err: net.Send_Error) {}

ping_handler :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_plain(res, "pong")
}

empty_handler :: proc(req: ^http.Request, res: ^http.Response) {
	res.status = .OK
	http.respond(res)
}

json_handler :: proc(req: ^http.Request, res: ^http.Response) {
	_ = http.respond_json(res, json_reply)
}

payload_handler :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_plain(res, JSON_STATIC)
}

events_handler :: proc(req: ^http.Request, res: ^http.Response) {
	stream := new(http.Sse, context.temp_allocator)
	http.sse_init(stream, res, on_error = on_sse_error, allocator = context.temp_allocator)
	http.sse_start(stream)
	http.sse_event(stream, http.Sse_Event{comment = "connected"})
	http.sse_event(stream, http.Sse_Event{retry = 1000})
	http.sse_event(stream, http.Sse_Event{event = "welcome", data = "ready"})
	schedule_tick(stream)
}

main :: proc() {
	server: http.Server
	http.server_shutdown_on_interrupt(&server)

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)

	http.route_get(&router, "/empty", http.handler(empty_handler))
	http.route_get(&router, "/ping", http.handler(ping_handler))
	http.route_get(&router, "/json", http.handler(json_handler))
	http.route_get(&router, "/plain", http.handler(payload_handler))
	http.route_get(&router, "/events", http.handler(events_handler))

	err := http.listen_and_serve(&server, http.router_handler(&router), net.Endpoint{address = net.IP4_Loopback, port = 6968})
	if err != nil {
		panic("raw odin compare server failed")
	}
}
