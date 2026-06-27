// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:net"

import http "../vendor/odin-http"

empty_handler :: proc(_: ^http.Request, res: ^http.Response) {
	res.status = .OK
	http.respond(res)
}

main :: proc() {
	server: http.Server
	http.server_shutdown_on_interrupt(&server)

	handler := http.handler(empty_handler)
	err := http.listen_and_serve(&server, handler, net.Endpoint{address = net.IP4_Loopback, port = 6968})
	if err != nil {
		panic("raw odin empty-ok server failed")
	}
}
