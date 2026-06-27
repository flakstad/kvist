#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

PING_REQUESTS="${PING_REQUESTS:-200000}"
JSON_REQUESTS="${JSON_REQUESTS:-200000}"
PLAIN_REQUESTS="${PLAIN_REQUESTS:-200000}"
CONCURRENCY="${CONCURRENCY:-100}"
REQUEST_SECONDS="${REQUEST_SECONDS:-15}"
MEM_SAMPLE_SECONDS="${MEM_SAMPLE_SECONDS:-5}"
ODIN_BENCH_FLAGS="${ODIN_BENCH_FLAGS:--o:speed -disable-assert -no-bounds-check}"
SSE_CONNECTIONS="${SSE_CONNECTIONS:-200}"
SSE_DURATION="${SSE_DURATION:-5}"
SSE_SOAK_CONNECTIONS="${SSE_SOAK_CONNECTIONS:-300}"
SSE_SOAK_DURATION="${SSE_SOAK_DURATION:-30}"
SSE_CHURN_CONNECTIONS="${SSE_CHURN_CONNECTIONS:-100}"
SSE_CHURN_ROUNDS="${SSE_CHURN_ROUNDS:-3}"
SSE_CHURN_DURATION="${SSE_CHURN_DURATION:-3}"

tmp_dir=$(mktemp -d)
compiler="$tmp_dir/kvist-current"
kvist_generated="$tmp_dir/http-stress-server.odin"
kvist_bin="$tmp_dir/http-stress-server.bin"
current_server_pid=""
timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
results_dir="${RESULTS_DIR:-$ROOT/benchmarks/results}"
results_file="$results_dir/http_compare_$timestamp.jsonl"

cleanup() {
    set +e
    if [ -n "$current_server_pid" ]; then
        kill "$current_server_pid" 2>/dev/null || true
        wait "$current_server_pid" 2>/dev/null || true
    fi
    rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$results_dir"

printf 'building current compiler\n'
odin build "$ROOT/cmd/kvist" -out:"$compiler"
printf 'building optimized kvist stress server\n'
"$compiler" compile "$ROOT/examples/web/http-stress-server.kvist" -o "$kvist_generated"
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

listener_pid() {
    listen_port="$1"
    lsof -tiTCP:"$listen_port" -sTCP:LISTEN 2>/dev/null | head -n 1
}

print_mem() {
    mem_label="$1"
    mem_port="$2"
    mem_pid=$(listener_pid "$mem_port")
    if [ -z "$mem_pid" ]; then
        printf '%s rss_kb=? vsz_kb=? fd_count=?\n' "$mem_label"
        return
    fi
    ps_line=$(ps -o rss=,vsz= -p "$mem_pid")
    rss=$(printf '%s\n' "$ps_line" | awk '{print $1}')
    vsz=$(printf '%s\n' "$ps_line" | awk '{print $2}')
    fd_count=$(lsof -p "$mem_pid" 2>/dev/null | wc -l | tr -d ' ')
    printf '%s rss_kb=%s vsz_kb=%s fd_count=%s\n' "$mem_label" "$rss" "$vsz" "$fd_count"
}

sample_mem_until_exit() {
    sample_target_pid="$1"
    sample_port="$2"
    sample_file="$3"
    sample_interval="$4"

    while kill -0 "$sample_target_pid" 2>/dev/null; do
        sample_mem_pid=$(listener_pid "$sample_port")
        if [ -n "$sample_mem_pid" ]; then
            sample_ps_line=$(ps -o rss=,vsz= -p "$sample_mem_pid")
            sample_rss=$(printf '%s\n' "$sample_ps_line" | awk '{print $1}')
            sample_vsz=$(printf '%s\n' "$sample_ps_line" | awk '{print $2}')
            sample_fd_count=$(lsof -p "$sample_mem_pid" 2>/dev/null | wc -l | tr -d ' ')
            printf '%s %s %s\n' "$sample_rss" "$sample_vsz" "$sample_fd_count" >>"$sample_file"
        fi
        sleep "$sample_interval"
    done
}

print_mem_summary() {
    summary_label="$1"
    summary_file="$2"
    if [ ! -s "$summary_file" ]; then
        printf '%s rss_kb_peak=? vsz_kb_peak=? fd_count_peak=?\n' "$summary_label"
        return
    fi

    peak_rss=$(awk 'BEGIN {m=0} {if ($1>m) m=$1} END {print m}' "$summary_file")
    peak_vsz=$(awk 'BEGIN {m=0} {if ($2>m) m=$2} END {print m}' "$summary_file")
    peak_fd=$(awk 'BEGIN {m=0} {if ($3>m) m=$3} END {print m}' "$summary_file")
    printf '%s rss_kb_peak=%s vsz_kb_peak=%s fd_count_peak=%s\n' "$summary_label" "$peak_rss" "$peak_vsz" "$peak_fd"
}

print_mem_growth() {
    growth_label="$1"
    growth_file="$2"
    if [ ! -s "$growth_file" ]; then
        printf '%s rss_kb_start=? rss_kb_end=? rss_kb_delta=?\n' "$growth_label"
        return
    fi

    start_rss=$(awk 'NR==1 {print $1}' "$growth_file")
    end_rss=$(awk 'END {print $1}' "$growth_file")
    delta_rss=$((end_rss - start_rss))
    printf '%s rss_kb_start=%s rss_kb_end=%s rss_kb_delta=%s\n' "$growth_label" "$start_rss" "$end_rss" "$delta_rss"
}

print_ab_percentiles() {
    ab_output_file="$1"
    awk '
        /^  50%/ {p50=$2}
        /^  66%/ {p66=$2}
        /^  75%/ {p75=$2}
        /^  80%/ {p80=$2}
        /^  90%/ {p90=$2}
        /^  95%/ {p95=$2}
        /^  98%/ {p98=$2}
        /^  99%/ {p99=$2}
        /^ 100%/ {p100=$2}
        END {
            printf "Latency percentiles (ms): p50=%s p90=%s p95=%s p99=%s p100=%s\n", p50, p90, p95, p99, p100
        }
    ' "$ab_output_file"
}

append_result() {
    phase_kind="$1"
    suite_name="$2"
    phase_name="$3"
    extra_json="$4"
    python3 - "$results_file" "$phase_kind" "$suite_name" "$phase_name" "$extra_json" <<'PY'
import json
import sys

path, kind, suite, phase, extra = sys.argv[1:]
record = {"kind": kind, "suite": suite, "phase": phase}
record.update(json.loads(extra))
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(record) + "\n")
PY
}

ab_summary_json() {
    ab_output_file="$1"
    mem_file="$2"
    python3 - "$ab_output_file" "$mem_file" <<'PY'
import json
import re
import sys

ab_path, mem_path = sys.argv[1:]
text = open(ab_path, encoding="utf-8").read()

def match(pattern):
    m = re.search(pattern, text, re.MULTILINE)
    return m.group(1) if m else None

summary = {
    "requests_per_sec": float(match(r"Requests per second:\s+([0-9.]+)")) if match(r"Requests per second:\s+([0-9.]+)") else None,
    "time_per_request_ms": float(match(r"Time per request:\s+([0-9.]+) \[ms\] \(mean\)")) if match(r"Time per request:\s+([0-9.]+) \[ms\] \(mean\)") else None,
    "failed_requests": int(match(r"Failed requests:\s+([0-9]+)")) if match(r"Failed requests:\s+([0-9]+)") else None,
    "non_2xx_responses": int(match(r"Non-2xx responses:\s+([0-9]+)")) if match(r"Non-2xx responses:\s+([0-9]+)") else 0,
    "p50_ms": int(match(r"^\s*50%\s+([0-9]+)")) if match(r"^\s*50%\s+([0-9]+)") else None,
    "p90_ms": int(match(r"^\s*90%\s+([0-9]+)")) if match(r"^\s*90%\s+([0-9]+)") else None,
    "p95_ms": int(match(r"^\s*95%\s+([0-9]+)")) if match(r"^\s*95%\s+([0-9]+)") else None,
    "p99_ms": int(match(r"^\s*99%\s+([0-9]+)")) if match(r"^\s*99%\s+([0-9]+)") else None,
    "p100_ms": int(match(r"^\s*100%\s+([0-9]+)")) if match(r"^\s*100%\s+([0-9]+)") else None,
}

samples = []
with open(mem_path, encoding="utf-8") as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) == 3:
            samples.append(tuple(int(x) for x in parts))

if samples:
    rss_vals = [s[0] for s in samples]
    vsz_vals = [s[1] for s in samples]
    fd_vals = [s[2] for s in samples]
    summary.update({
        "rss_kb_peak": max(rss_vals),
        "rss_kb_start": rss_vals[0],
        "rss_kb_end": rss_vals[-1],
        "rss_kb_delta": rss_vals[-1] - rss_vals[0],
        "vsz_kb_peak": max(vsz_vals),
        "fd_count_peak": max(fd_vals),
    })

print(json.dumps(summary))
PY
}

sse_summary_json() {
    sse_json_file="$1"
    mem_file="$2"
    python3 - "$sse_json_file" "$mem_file" <<'PY'
import json
import sys

sse_path, mem_path = sys.argv[1:]
summary = json.load(open(sse_path, encoding="utf-8"))
samples = []
with open(mem_path, encoding="utf-8") as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) == 3:
            samples.append(tuple(int(x) for x in parts))

if samples:
    rss_vals = [s[0] for s in samples]
    vsz_vals = [s[1] for s in samples]
    fd_vals = [s[2] for s in samples]
    summary.update({
        "rss_kb_peak": max(rss_vals),
        "rss_kb_start": rss_vals[0],
        "rss_kb_end": rss_vals[-1],
        "rss_kb_delta": rss_vals[-1] - rss_vals[0],
        "vsz_kb_peak": max(vsz_vals),
        "fd_count_peak": max(fd_vals),
    })

print(json.dumps(summary))
PY
}

run_ab() {
    suite_name="$1"
    phase_name="$2"
    port="$3"
    path="$4"
    requests="$5"
    label="$suite_name-$phase_name"
    output_file="$tmp_dir/$label.ab"
    mem_file="$tmp_dir/$label.mem"
    printf '\n== %s ==\n' "$label"
    print_mem "before-$label" "$port"
    : >"$mem_file"
    ab -n "$requests" -t "$REQUEST_SECONDS" -c "$CONCURRENCY" "http://127.0.0.1:$port$path" >"$output_file" 2>&1 &
    sample_pid=$!
    sample_mem_until_exit "$sample_pid" "$port" "$mem_file" "$MEM_SAMPLE_SECONDS" &
    sampler_pid=$!
    wait "$sample_pid"
    wait "$sampler_pid" 2>/dev/null || true
    awk '
        /Requests per second/ {print}
        /Time per request/ {print}
        /Failed requests/ {print}
        /Non-2xx responses/ {print}
    ' "$output_file"
    print_ab_percentiles "$output_file"
    print_mem_summary "peak-$label" "$mem_file"
    print_mem "after-$label" "$port"
    append_result "http" "$suite_name" "$phase_name" "$(ab_summary_json "$output_file" "$mem_file")"
}

run_sse_steady() {
    suite_name="$1"
    phase_name="$2"
    port="$3"
    connections="$4"
    duration="$5"
    label="$suite_name-$phase_name"
    mem_file="$tmp_dir/$label.mem"
    printf '\n== %s ==\n' "$label"
    print_mem "before-$label" "$port"
    : >"$mem_file"
    python3 "$ROOT/scripts/sse_probe.py" \
        --url "http://127.0.0.1:$port/events" \
        --connections "$connections" \
        --duration "$duration" >"$tmp_dir/$label.json" &
    probe_pid=$!
    sample_mem_until_exit "$probe_pid" "$port" "$mem_file" "$MEM_SAMPLE_SECONDS" &
    sampler_pid=$!
    wait "$probe_pid"
    wait "$sampler_pid" 2>/dev/null || true
    print_mem "after-$label" "$port"
    print_mem_summary "peak-$label" "$mem_file"
    print_mem_growth "growth-$label" "$mem_file"
    cat "$tmp_dir/$label.json"
    append_result "sse" "$suite_name" "$phase_name" "$(sse_summary_json "$tmp_dir/$label.json" "$mem_file")"
}

run_sse_churn() {
    label="$1"
    port="$2"
    printf '\n== %s ==\n' "$label"
    print_mem "before-$label" "$port"
    round=1
    while [ "$round" -le "$SSE_CHURN_ROUNDS" ]; do
        probe_output=$(python3 "$ROOT/scripts/sse_probe.py" \
            --url "http://127.0.0.1:$port/events" \
            --connections "$SSE_CHURN_CONNECTIONS" \
            --duration "$SSE_CHURN_DURATION")
        printf 'round %s %s\n' "$round" "$probe_output"
        print_mem "after-$label-round-$round" "$port"
        round=$((round + 1))
    done
    print_mem "after-$label" "$port"
}

run_suite() {
    name="$1"
    port="$2"
    cmd="$3"
    log="$tmp_dir/$name.log"

    printf '\n================ %s ================\n' "$name"
    sh -c "$cmd" >"$log" 2>&1 &
    current_server_pid=$!

    wait_for_server "$port" "$log"

    run_ab "$name" "ping" "$port" "/ping" "$PING_REQUESTS"
    run_ab "$name" "json" "$port" "/json" "$JSON_REQUESTS"
    run_ab "$name" "plain" "$port" "/plain" "$PLAIN_REQUESTS"
    run_sse_steady "$name" "sse-steady" "$port" "$SSE_CONNECTIONS" "$SSE_DURATION"
    run_sse_steady "$name" "sse-soak" "$port" "$SSE_SOAK_CONNECTIONS" "$SSE_SOAK_DURATION"
    run_sse_churn "$name-sse-churn" "$port"

    kill "$current_server_pid" 2>/dev/null || true
    wait "$current_server_pid" 2>/dev/null || true
    current_server_pid=""
}

run_basic_suite() {
    name="$1"
    port="$2"
    cmd="$3"
    log="$tmp_dir/$name.log"

    printf '\n================ %s ================\n' "$name"
    sh -c "$cmd" >"$log" 2>&1 &
    current_server_pid=$!

    wait_for_server "$port" "$log"

    run_ab "$name" "ping" "$port" "/ping" "$PING_REQUESTS"
    run_ab "$name" "plain" "$port" "/plain" "$PLAIN_REQUESTS"

    kill "$current_server_pid" 2>/dev/null || true
    wait "$current_server_pid" 2>/dev/null || true
    current_server_pid=""
}

run_suite \
    "kvist" \
    "6969" \
    "cd \"$ROOT\" && \"$kvist_bin\""

run_basic_suite \
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

printf '\nresults_file %s\n' "$results_file"
