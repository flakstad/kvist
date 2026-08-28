#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

requests="$tmp_dir/requests.jsonl"
events="$tmp_dir/events.jsonl"

if [ "${KVIST_BENCH_COMPILER:-}" ]; then
    compiler=$KVIST_BENCH_COMPILER
else
    compiler="$tmp_dir/kvist"
    odin build "$ROOT/src/cli/kvist" -o:speed -out:"$compiler"
fi

cat >"$requests" <<'JSONL'
{"id":"minimal-array","op":"eval","source":"(baseline-pair 20 22)"}
{"id":"load-data","op":"eval","source":"(import data \"kvist:data\")\n(defn profile-card [name: string, role: string] -> Data\n  [:article {:class \"profile\"}\n   [:h2 name]\n   [:p role]])","source_path":"/virtual/repl-native-packages.kvist","line":1,"column":1,"no_print":true,"defer_debug_values":true}
{"id":"profile-direct","op":"eval","source":"(profile-card \"Ada Lovelace\" \"Mathematician\")"}
{"id":"data-get-1","op":"eval","source":"(get (profile-card \"Ada Lovelace\" \"Mathematician\") 0)"}
{"id":"data-first","op":"eval","source":"(data.first (profile-card \"Ada Lovelace\" \"Mathematician\"))"}
{"id":"data-get-2","op":"eval","source":"(get (profile-card \"Ada Lovelace\" \"Mathematician\") 0)"}
{"id":"reset-before-arr","op":"reset"}
{"id":"load-arr","op":"eval","source":"(import arr \"kvist:arr\")","no_print":true,"defer_debug_values":true}
{"id":"arr-fixed-1","op":"eval","source":"(arr.fixed int [1 2 3])"}
{"id":"arr-fixed-2","op":"eval","source":"(arr.fixed int [1 2 3])"}
{"id":"close","op":"close"}
JSONL

KVIST_ROOT="$ROOT/src/kvist" \
    "$compiler" repl "$ROOT/benchmarks/repl_native_packages.kvist" \
    --protocol jsonl <"$requests" >"$events"

awk '
function text_field(line, key,    needle, rest) {
    needle = "\"" key "\":\""
    if (index(line, needle) == 0) return ""
    rest = substr(line, index(line, needle) + length(needle))
    sub(/\".*/, "", rest)
    return rest
}
function int_field(line, key,    needle, rest) {
    needle = "\"" key "\":"
    if (index(line, needle) == 0) return 0
    rest = substr(line, index(line, needle) + length(needle))
    sub(/[^0-9].*/, "", rest)
    return rest + 0
}
function bool_field(line, key,    needle, rest) {
    needle = "\"" key "\":"
    if (index(line, needle) == 0) return "false"
    rest = substr(line, index(line, needle) + length(needle))
    return substr(rest, 1, 4) == "true" ? "true" : "false"
}
function phase_ms(line, phase,    needle, rest) {
    needle = "\"phase\":\"" phase "\",\"elapsed_ns\":"
    if (index(line, needle) == 0) return 0
    rest = substr(line, index(line, needle) + length(needle))
    sub(/[^0-9].*/, "", rest)
    return (rest + 0) / 1000000.0
}
BEGIN {
    print "id\tbytes\tfrontend_ms\temission_ms\todin_ms\tworker_load_ms\tnative_ms\ttotal_ms\tfrontend_cache\tnative_cache"
}
/\"kind\":\"timings\"/ {
    printf "%s\t%d\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%s\t%s\n",
        text_field($0, "id"),
        int_field($0, "generated_bytes"),
        phase_ms($0, "frontend-total"),
        phase_ms($0, "frontend-emission"),
        phase_ms($0, "odin-build"),
        phase_ms($0, "worker-load"),
        phase_ms($0, "native-run"),
        phase_ms($0, "controller-total"),
        bool_field($0, "frontend_cache_hit"),
        bool_field($0, "native_cache_hit")
}
' "$events"
