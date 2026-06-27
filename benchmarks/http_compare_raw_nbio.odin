// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:nbio"
import "core:net"
import "core:strings"

JSON_STATIC: string : "{\"message\":\"pong\",\"count\":1,\"ok\":true,\"service\":\"raw-nbio\",\"env\":\"bench\",\"user\":\"load-test\",\"stats\":{\"latency_ms\":12,\"cpu_pct\":37,\"mem_mb\":128},\"meta\":{\"request_id\":\"req-123456789\",\"build\":\"2026.06.01\",\"region\":\"eu-north-1\"},\"note\":\"Longer JSON payload for rough comparison.\"}"

Conn :: struct {
	socket:   net.TCP_Socket,
	recv_buf: [2048]byte,
}

EMPTY_RESPONSE :: "HTTP/1.1 200\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
PING_RESPONSE :: "HTTP/1.1 200\r\nContent-Length: 4\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\npong"

PLAIN_RESPONSE :: "HTTP/1.1 200\r\nContent-Length: 278\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n{\"message\":\"pong\",\"count\":1,\"ok\":true,\"service\":\"raw-nbio\",\"env\":\"bench\",\"user\":\"load-test\",\"stats\":{\"latency_ms\":12,\"cpu_pct\":37,\"mem_mb\":128},\"meta\":{\"request_id\":\"req-123456789\",\"build\":\"2026.06.01\",\"region\":\"eu-north-1\"},\"note\":\"Longer JSON payload for rough comparison.\"}"

NOT_FOUND_RESPONSE := "HTTP/1.1 404\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

close_conn :: proc(conn: ^Conn) {
	nbio.close_poly(conn.socket, conn, proc(_: ^nbio.Operation, conn: ^Conn) {
		free(conn)
	})
}

send_response :: proc(conn: ^Conn, response: string) {
	nbio.send_poly(conn.socket, {transmute([]byte)response}, conn, proc(op: ^nbio.Operation, conn: ^Conn) {
		close_conn(conn)
	})
}

parse_response :: proc(buf: []byte, n: int) -> string {
	request := string(buf[:n])
	if strings.has_prefix(request, "GET /empty ") {
		return EMPTY_RESPONSE
	}
	if strings.has_prefix(request, "GET /ping ") {
		return PING_RESPONSE
	}
	if strings.has_prefix(request, "GET /plain ") {
		return PLAIN_RESPONSE
	}
	return NOT_FOUND_RESPONSE
}

on_recv :: proc(op: ^nbio.Operation, conn: ^Conn) {
	if op.recv.err != nil || op.recv.received <= 0 {
		close_conn(conn)
		return
	}

	send_response(conn, parse_response(conn.recv_buf[:], op.recv.received))
}

on_accept :: proc(op: ^nbio.Operation, server: net.TCP_Socket) {
	if op.accept.err == nil {
		conn := new(Conn, context.allocator)
		conn.socket = op.accept.client
		nbio.recv_poly(conn.socket, {conn.recv_buf[:]}, conn, on_recv)
	}

	nbio.accept_poly(server, server, on_accept)
}

main :: proc() {
	err := nbio.acquire_thread_event_loop()
	if err != nil {
		panic("failed to acquire event loop")
	}
	defer nbio.release_thread_event_loop()

	server, listen_err := nbio.listen_tcp(net.Endpoint{address = net.IP4_Loopback, port = 6967})
	if listen_err != nil {
		panic("failed to listen")
	}

	nbio.accept_poly(server, server, on_accept)

	run_err := nbio.run()
	if run_err != nil {
		panic("nbio run failed")
	}
}
