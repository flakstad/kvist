package kvist_map

// A key/value pair yielded by map.entries in fused transform pipelines.
entry :: struct($K: typeid, $V: typeid) {
	key:   K,
	value: V,
}
