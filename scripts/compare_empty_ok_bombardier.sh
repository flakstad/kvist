#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

ODIN_BENCH_FLAGS="${ODIN_BENCH_FLAGS:--o:speed -disable-assert -no-bounds-check}"
CONNECTIONS="${CONNECTIONS:-250}"
REQUESTS="${REQUESTS:-200000}"
CLIENT="${CLIENT:-http1}"
TIMEOUT="${TIMEOUT:-10s}"
KEEPALIVE="${KEEPALIVE:-1}"

tmp_dir=$(mktemp -d)
compiler="$tmp_dir/kvist-current"
kvist_generated="$tmp_dir/http_empty_ok.odin"
kvist_bin="$tmp_dir/http_empty_ok.bin"
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
printf 'building kvist empty-ok benchmark server\n'
"$compiler" compile "$ROOT/benchmarks/http_compare_empty_ok.kvist" -o "$kvist_generated"
odin build "$kvist_generated" -file $ODIN_BENCH_FLAGS -out:"$kvist_bin"

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
    json_file="$2"
    python3 - "$suite" "$json_file" <<'PY'
import json
import sys

suite, path = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
r = data["result"]
lat = r["latency"]["percentiles"]
errors = sum(e["count"] for e in r.get("errors", []))
print(f"{suite}: "
      f"rps={r['rps']['mean']:.2f} "
      f"lat_mean_ms={r['latency']['mean'] / 1000.0:.3f} "
      f"p50={lat.get('50')}us p90={lat.get('90')}us p95={lat.get('95')}us p99={lat.get('99')}us "
      f"2xx={r['req2xx']} errors={errors}")
PY
}

run_bench() {
    suite="$1"
    port="$2"
    out="$tmp_dir/$suite.json"
    bombardier $(bombardier_flags) "http://127.0.0.1:$port/" >"$out"
    print_result "$suite" "$out"
}

run_suite() {
    name="$1"
    port="$2"
    command="$3"
    printf '\n================ %s ================\n' "$name"
    run_server "$name" "$port" "$command"
    run_bench "$name" "$port"
}

run_suite \
    "kvist" \
    "6969" \
    "\"$kvist_bin\""

run_suite \
    "odin-raw" \
    "6968" \
    "cd \"$ROOT\" && odin build benchmarks/http_compare_empty_ok_raw_odin.odin -file $ODIN_BENCH_FLAGS -out:\"$tmp_dir/http_compare_empty_ok_raw_odin.bin\" >/dev/null && \"$tmp_dir/http_compare_empty_ok_raw_odin.bin\""

run_suite \
    "clojure" \
    "6970" \
    "cd \"$ROOT/benchmarks/clojure_http_compare\" && PORT=6970 clojure -M -m bench.empty-ok"
