package main

import "core:net"

import http "../vendor/odin-http"

pong_handler :: proc(_: ^http.Request, res: ^http.Response) {
	http.respond_plain(res, "pong")
}

main :: proc() {
	server: http.Server
	http.server_shutdown_on_interrupt(&server)

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)

	http.route_get(&router, "/", http.handler(pong_handler))

	err := http.listen_and_serve(&server, http.router_handler(&router), net.Endpoint{address = net.IP4_Loopback, port = 6968})
	if err != nil {
		panic("raw odin pong-routed server failed")
	}
}
