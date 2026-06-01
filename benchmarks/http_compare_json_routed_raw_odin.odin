package main

import "core:net"

import http "../vendor/odin-http"

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

json_handler :: proc(_: ^http.Request, res: ^http.Response) {
	_ = http.respond_json(res, json_reply)
}

main :: proc() {
	server: http.Server
	http.server_shutdown_on_interrupt(&server)

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)

	http.route_get(&router, "/", http.handler(json_handler))

	err := http.listen_and_serve(&server, http.router_handler(&router), net.Endpoint{address = net.IP4_Loopback, port = 6968})
	if err != nil {
		panic("raw odin json-routed server failed")
	}
}
