#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

ODIN_BENCH_FLAGS="${ODIN_BENCH_FLAGS:--o:speed -disable-assert -no-bounds-check}"
BOMBARDIER_CONNECTIONS="${BOMBARDIER_CONNECTIONS:-125}"
BOMBARDIER_DURATION="${BOMBARDIER_DURATION:-10s}"
BOMBARDIER_TIMEOUT="${BOMBARDIER_TIMEOUT:-2s}"
BOMBARDIER_CLIENT="${BOMBARDIER_CLIENT:-http1}"
DISABLE_KEEPALIVES="${DISABLE_KEEPALIVES:-1}"

tmp_dir=$(mktemp -d)
compiler="$tmp_dir/kvist-current"
kvist_generated="$tmp_dir/http-stress-server.odin"
kvist_bin="$tmp_dir/http-stress-server.bin"
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
printf 'building optimized kvist stress server\n'
"$compiler" compile "$ROOT/examples/http-stress-server.kvist" -o "$kvist_generated"
odin build "$kvist_generated" -file $ODIN_BENCH_FLAGS -out:"$kvist_bin"

wait_for_server() {
    wait_port="$1"
    wait_log="$2"
    i=0
    while [ "$i" -lt 100 ]; do
        if curl -fsS "http://127.0.0.1:$wait_port/ping" >/dev/null 2>&1; then
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
    flags="-c $BOMBARDIER_CONNECTIONS -d $BOMBARDIER_DURATION -t $BOMBARDIER_TIMEOUT -l -o json -p r"
    case "$BOMBARDIER_CLIENT" in
        fasthttp) ;;
        http1) flags="$flags --http1" ;;
        http2) flags="$flags --http2" ;;
        *) printf 'unknown BOMBARDIER_CLIENT: %s\n' "$BOMBARDIER_CLIENT" >&2; exit 1 ;;
    esac
    if [ "$DISABLE_KEEPALIVES" = "1" ]; then
        flags="$flags -a"
    fi
    printf '%s' "$flags"
}

print_result() {
    suite="$1"
    endpoint="$2"
    json_file="$3"
    python3 - "$suite" "$endpoint" "$json_file" <<'PY'
import json
import sys

suite, endpoint, path = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
r = data["result"]
lat = r["latency"]["percentiles"]
print(f"{suite} {endpoint}: "
      f"rps={r['rps']['mean']:.2f} "
      f"lat_mean_ms={r['latency']['mean']:.2f} "
      f"p50={lat.get('50')} p90={lat.get('90')} p95={lat.get('95')} p99={lat.get('99')} "
      f"2xx={r['req2xx']} 4xx={r['req4xx']} 5xx={r['req5xx']} errors={sum(e['count'] for e in r['errors']) if r.get('errors') else 0}")
PY
}

run_bombardier() {
    suite="$1"
    port="$2"
    endpoint="$3"
    if [ "$suite" = "odin-nbio" ] && [ "$endpoint" = "json" ]; then
        return
    fi
    if [ "$suite" = "odin-nbio" ] && [ "$endpoint" = "events" ]; then
        return
    fi

    url="http://127.0.0.1:$port/$endpoint"
    out="$tmp_dir/${suite}_${endpoint}.json"
    bombardier $(bombardier_flags) "$url" >"$out"
    print_result "$suite" "$endpoint" "$out"
}

run_suite() {
    name="$1"
    port="$2"
    command="$3"
    printf '\n================ %s ================\n' "$name"
    run_server "$name" "$port" "$command"
    run_bombardier "$name" "$port" "empty"
    run_bombardier "$name" "$port" "ping"
    run_bombardier "$name" "$port" "json"
    run_bombardier "$name" "$port" "plain"
}

run_suite \
    "kvist" \
    "6969" \
    "\"$kvist_bin\""

run_suite \
    "odin-nbio" \
    "6967" \
    "cd \"$ROOT\" && odin build benchmarks/http_compare_raw_nbio.odin -file $ODIN_BENCH_FLAGS -out:\"$tmp_dir/http_compare_raw_nbio.bin\" >/dev/null && \"$tmp_dir/http_compare_raw_nbio.bin\""

run_suite \
    "odin-raw" \
    "6968" \
    "cd \"$ROOT\" && odin build benchmarks/http_compare_raw_odin.odin -file $ODIN_BENCH_FLAGS -out:\"$tmp_dir/http_compare_raw_odin.bin\" >/dev/null && \"$tmp_dir/http_compare_raw_odin.bin\""

run_suite \
    "clojure" \
    "6970" \
    "cd \"$ROOT/benchmarks/clojure_http_compare\" && PORT=6970 clojure -M -m bench.http-compare"
