#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

ODIN_BENCH_FLAGS="${ODIN_BENCH_FLAGS:--o:speed -disable-assert -no-bounds-check}"
CONNECTIONS="${CONNECTIONS:-100}"
REQUESTS="${REQUESTS:-100000}"
CLIENT="${CLIENT:-http1}"
TIMEOUT="${TIMEOUT:-10s}"
KEEPALIVE="${KEEPALIVE:-1}"
SHAPES="${SHAPES:-pong plain json}"

tmp_dir=$(mktemp -d)
compiler="$tmp_dir/kvist-current"
current_server_pid=""

cleanup() {
    set +e
    if [ -n "$current_server_pid" ]; then
        kill "$current_server_pid" 2>/dev/null || true
        wait "$current_server_pid" 2>/dev/null || true
    fi
    rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

printf 'building current compiler\n'
odin build "$ROOT/cmd/kvist" -out:"$compiler"

wait_for_server() {
    wait_port="$1"
    wait_log="$2"
    i=0
    while [ "$i" -lt 100 ]; do
        if curl -fsS "http://127.0.0.1:$wait_port/" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    printf 'server failed to start on port %s\n' "$wait_port" >&2
    sed -n '1,220p' "$wait_log" >&2 || true
    return 1
}

run_server() {
    name="$1"
    port="$2"
    command="$3"
    log_file="$tmp_dir/$name.log"

    if [ -n "$current_server_pid" ]; then
        kill "$current_server_pid" 2>/dev/null || true
        wait "$current_server_pid" 2>/dev/null || true
        current_server_pid=""
    fi

    sh -c "$command" >"$log_file" 2>&1 &
    current_server_pid=$!
    wait_for_server "$port" "$log_file"
}

bombardier_flags() {
    flags="-c $CONNECTIONS -n $REQUESTS -t $TIMEOUT -l -o json -p r"
    case "$CLIENT" in
        fasthttp) ;;
        http1) flags="$flags --http1" ;;
        http2) flags="$flags --http2" ;;
        *) printf 'unknown CLIENT: %s\n' "$CLIENT" >&2; exit 1 ;;
    esac
    if [ "$KEEPALIVE" != "1" ]; then
        flags="$flags -a"
    fi
    printf '%s' "$flags"
}

print_result() {
    suite="$1"
    style="$2"
    shape="$3"
    json_file="$4"
    python3 - "$suite" "$style" "$shape" "$json_file" <<'PY'
import json
import sys

suite, style, shape, path = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
r = data["result"]
lat = r["latency"]["percentiles"]
errors = sum(e["count"] for e in r.get("errors", []))
print(f"{suite} {style} {shape}: "
      f"rps={r['rps']['mean']:.2f} "
      f"lat_mean_ms={r['latency']['mean'] / 1000.0:.3f} "
      f"p50={lat.get('50')}us p90={lat.get('90')}us p95={lat.get('95')}us p99={lat.get('99')}us "
      f"2xx={r['req2xx']} 4xx={r['req4xx']} 5xx={r['req5xx']} errors={errors}")
PY
}

run_bench() {
    suite="$1"
    style="$2"
    shape="$3"
    port="$4"
    out="$tmp_dir/${suite}_${style}_${shape}.json"
    bombardier $(bombardier_flags) "http://127.0.0.1:$port/" >"$out"
    print_result "$suite" "$style" "$shape" "$out"
}

for shape in $SHAPES; do
    printf '\n================ shape=%s ================\n' "$shape"

    case "$shape" in
        pong)
            kvist_direct_src="$ROOT/benchmarks/http_compare_pong_ok.kvist"
            kvist_routed_src="$ROOT/benchmarks/http_compare_pong_routed.kvist"
            raw_direct_src="$ROOT/benchmarks/http_compare_pong_ok_raw_odin.odin"
            raw_routed_src="$ROOT/benchmarks/http_compare_pong_routed_raw_odin.odin"
            ;;
        plain)
            kvist_direct_src="$ROOT/benchmarks/http_compare_plain_static.kvist"
            kvist_routed_src="$ROOT/benchmarks/http_compare_plain_routed.kvist"
            raw_direct_src="$ROOT/benchmarks/http_compare_plain_static_raw_odin.odin"
            raw_routed_src="$ROOT/benchmarks/http_compare_plain_routed_raw_odin.odin"
            ;;
        json)
            kvist_direct_src="$ROOT/benchmarks/http_compare_json_marshal.kvist"
            kvist_routed_src="$ROOT/benchmarks/http_compare_json_routed.kvist"
            raw_direct_src="$ROOT/benchmarks/http_compare_json_marshal_raw_odin.odin"
            raw_routed_src="$ROOT/benchmarks/http_compare_json_routed_raw_odin.odin"
            ;;
        *)
            printf 'unknown shape: %s\n' "$shape" >&2
            exit 1
            ;;
    esac

    kvist_generated="$tmp_dir/http_${shape}_direct.odin"
    kvist_bin="$tmp_dir/http_${shape}_direct.bin"
    "$compiler" compile "$kvist_direct_src" -o "$kvist_generated"
    odin build "$kvist_generated" -file $ODIN_BENCH_FLAGS -out:"$kvist_bin"
    run_server "kvist-direct-$shape" "6969" "\"$kvist_bin\""
    run_bench "kvist" "direct" "$shape" "6969"

    kvist_generated="$tmp_dir/http_${shape}_routed.odin"
    kvist_bin="$tmp_dir/http_${shape}_routed.bin"
    "$compiler" compile "$kvist_routed_src" -o "$kvist_generated"
    odin build "$kvist_generated" -file $ODIN_BENCH_FLAGS -out:"$kvist_bin"
    run_server "kvist-routed-$shape" "6969" "\"$kvist_bin\""
    run_bench "kvist" "routed" "$shape" "6969"

    raw_bin="$tmp_dir/http_${shape}_direct_raw.bin"
    odin build "$raw_direct_src" -file $ODIN_BENCH_FLAGS -out:"$raw_bin"
    run_server "odin-raw-direct-$shape" "6968" "\"$raw_bin\""
    run_bench "odin-raw" "direct" "$shape" "6968"

    raw_bin="$tmp_dir/http_${shape}_routed_raw.bin"
    odin build "$raw_routed_src" -file $ODIN_BENCH_FLAGS -out:"$raw_bin"
    run_server "odin-raw-routed-$shape" "6968" "\"$raw_bin\""
    run_bench "odin-raw" "routed" "$shape" "6968"
done
