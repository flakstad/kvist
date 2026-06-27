// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:net"

import http "../vendor/odin-http"

JSON_STATIC: string : "{\"message\":\"pong\",\"count\":1,\"ok\":true,\"service\":\"odin-http\",\"env\":\"bench\",\"user\":\"load-test\",\"stats\":{\"latency_ms\":12,\"cpu_pct\":37,\"mem_mb\":128},\"meta\":{\"request_id\":\"req-123456789\",\"build\":\"2026.06.01\",\"region\":\"eu-north-1\"},\"note\":\"Longer JSON payload for rough comparison.\"}"

plain_handler :: proc(_: ^http.Request, res: ^http.Response) {
	http.respond_plain(res, JSON_STATIC)
}

main :: proc() {
	server: http.Server
	http.server_shutdown_on_interrupt(&server)

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)

	http.route_get(&router, "/", http.handler(plain_handler))

	err := http.listen_and_serve(&server, http.router_handler(&router), net.Endpoint{address = net.IP4_Loopback, port = 6968})
	if err != nil {
		panic("raw odin plain-routed server failed")
	}
}
