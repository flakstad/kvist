package mpsc

import "base:intrinsics"
import list "core:container/intrusive/list"

// Queue is a lock-free multi-producer, single-consumer intrusive queue.
// Based on Dmitry Vyukov's MPSC algorithm.
Queue :: struct($T: typeid) {
	head: ^list.Node,
	tail: ^list.Node,
	stub: list.Node,
	len:  int,
}

init :: proc(q: ^Queue($T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	q.stub.next = nil
	q.head = &q.stub
	q.tail = &q.stub
	q.len = 0
}

push :: proc(q: ^Queue($T), msg: ^Maybe(^T)) -> bool where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	if msg == nil || msg^ == nil {
		return false
	}

	ptr := (msg^).?
	node := &ptr.node

	intrinsics.atomic_store(&node.next, nil)
	prev := intrinsics.atomic_exchange(&q.head, node)
	intrinsics.atomic_store(&prev.next, node)
	intrinsics.atomic_add(&q.len, 1)

	msg^ = nil
	return true
}

pop :: proc(q: ^Queue($T)) -> ^T where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	tail := q.tail
	next := intrinsics.atomic_load(&tail.next)

	if tail == &q.stub {
		if next == nil {
			return nil
		}
		q.tail = next
		tail = next
		next = intrinsics.atomic_load(&tail.next)
	}

	if next != nil {
		q.tail = next
		intrinsics.atomic_sub(&q.len, 1)
		return container_of(tail, T, "node")
	}

	head := intrinsics.atomic_load(&q.head)
	if tail != head {
		return nil
	}

	q.stub.next = nil
	prev := intrinsics.atomic_exchange(&q.head, &q.stub)
	intrinsics.atomic_store(&prev.next, &q.stub)

	next = intrinsics.atomic_load(&tail.next)
	if next != nil {
		q.tail = next
		intrinsics.atomic_sub(&q.len, 1)
		return container_of(tail, T, "node")
	}

	return nil
}

length :: proc(q: ^Queue($T)) -> int where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	return intrinsics.atomic_load(&q.len)
}
