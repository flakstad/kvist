#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

PORT="6969"
REQUESTS_PING="${REQUESTS_PING:-20000}"
REQUESTS_JSON="${REQUESTS_JSON:-20000}"
CONCURRENCY="${CONCURRENCY:-100}"
SSE_COUNTS="${SSE_COUNTS:-50 100 200}"
SSE_DURATION="${SSE_DURATION:-5}"
SSE_WARMUP="${SSE_WARMUP:-2}"
SSE_CHURN_COUNT="${SSE_CHURN_COUNT:-100}"
SSE_CHURN_ROUNDS="${SSE_CHURN_ROUNDS:-3}"
SSE_CHURN_DURATION="${SSE_CHURN_DURATION:-3}"

tmp_dir=$(mktemp -d)
server_pid=""
listener_pid=""
curl_pids=""

cleanup() {
    set +e
    for pid in $curl_pids; do
        kill "$pid" 2>/dev/null || true
    done
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

compiler="$tmp_dir/kvist-current"

printf 'building current compiler\n'
odin build "$ROOT/cmd/kvist" -out:"$compiler"

printf 'starting stress server on port %s\n' "$PORT"
(
    cd "$ROOT"
    "$compiler" run examples/http-stress-server.kvist --generated "$tmp_dir/http-stress-server.odin"
) >"$tmp_dir/server.log" 2>&1 &
server_pid=$!

server_listener_pid() {
    lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1
}

server_child_pid() {
    if [ -n "$listener_pid" ] && kill -0 "$listener_pid" 2>/dev/null; then
        printf '%s\n' "$listener_pid"
        return 0
    fi
    if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
        child=$(pgrep -P "$server_pid" | head -n 1 || true)
        if [ -n "$child" ]; then
            printf '%s\n' "$child"
            return 0
        fi
        printf '%s\n' "$server_pid"
        return 0
    fi
    return 1
}

server_process_pid_retry() {
    i=0
    while [ "$i" -lt 20 ]; do
        pid=$(server_child_pid || true)
        if [ -n "$pid" ]; then
            printf '%s\n' "$pid"
            return 0
        fi
        pid=$(server_listener_pid)
        if [ -n "$pid" ]; then
            printf '%s\n' "$pid"
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

require_server_alive() {
    label="$1"
    pid=$(server_process_pid_retry || true)
    if [ -z "$pid" ]; then
        printf 'server stopped during %s\n' "$label" >&2
        if [ -f "$tmp_dir/server.log" ]; then
            sed -n '1,220p' "$tmp_dir/server.log" >&2 || true
        fi
        exit 1
    fi
}

wait_for_server() {
    i=0
    while [ "$i" -lt 50 ]; do
        if curl -fsS "http://127.0.0.1:$PORT/ping" >/dev/null 2>&1; then
            listener_pid=$(server_listener_pid)
            return 0
        fi
        sleep 0.2
        i=$((i + 1))
    done
    printf 'server failed to start\n' >&2
    sed -n '1,160p' "$tmp_dir/server.log" >&2 || true
    return 1
}

wait_for_server

print_mem() {
    label="$1"
    pid=$(server_process_pid_retry || true)
    if [ -z "$pid" ]; then
        printf '%s rss_kb=? vsz_kb=? fd_count=?\n' "$label"
        return
    fi

    ps_line=$(ps -o rss=,vsz= -p "$pid")
    rss=$(printf '%s\n' "$ps_line" | awk '{print $1}')
    vsz=$(printf '%s\n' "$ps_line" | awk '{print $2}')
    fd_count=$(lsof -p "$pid" 2>/dev/null | wc -l | tr -d ' ')
    printf '%s rss_kb=%s vsz_kb=%s fd_count=%s\n' "$label" "$rss" "$vsz" "$fd_count"
}

run_ab_trial() {
    label="$1"
    requests="$2"
    path="$3"

    printf '\n== %s ==\n' "$label"
    print_mem "before-$label"
    ab -q -n "$requests" -c "$CONCURRENCY" "http://127.0.0.1:$PORT$path" | awk '
    /Requests per second/ {print}
    /Time per request/ {print}
    /Failed requests/ {print}
    /Non-2xx responses/ {print}
'
    print_mem "after-$label"
}

run_ab_trial "plain requests" "$REQUESTS_PING" "/ping"
run_ab_trial "json requests" "$REQUESTS_JSON" "/json"

run_sse_trial() {
    count="$1"
    trial_dir="$tmp_dir/sse-$count"
    mkdir -p "$trial_dir"
    curl_pids=""
    total_time=$((SSE_WARMUP + SSE_DURATION + 3))

    printf '\n== sse connections: %s ==\n' "$count"
    print_mem "before-sse-$count"
    i=1
    while [ "$i" -le "$count" ]; do
        curl -N -sS --max-time "$total_time" "http://127.0.0.1:$PORT/events" >"$trial_dir/$i.out" 2>"$trial_dir/$i.err" &
        pid="$!"
        curl_pids="$curl_pids $pid"
        printf '%s\n' "$pid" >"$trial_dir/$i.pid"
        i=$((i + 1))
    done

    sleep "$SSE_WARMUP"
    print_mem "warm-sse-$count"

    ready_warm=0
    i=1
    while [ "$i" -le "$count" ]; do
        if grep -q "data: ready" "$trial_dir/$i.out" 2>/dev/null; then
            ready_warm=$((ready_warm + 1))
        fi
        i=$((i + 1))
    done

    sleep "$SSE_DURATION"
    print_mem "during-sse-$count"

    for pid in $curl_pids; do
        wait "$pid" 2>/dev/null || true
    done

    tick_end=0
    bytes_end=0
    err_end=0
    i=1
    while [ "$i" -le "$count" ]; do
        if grep -q "event: tick" "$trial_dir/$i.out" 2>/dev/null; then
            tick_end=$((tick_end + 1))
        fi
        if [ -s "$trial_dir/$i.err" ]; then
            err_end=$((err_end + 1))
        fi
        size=$(wc -c <"$trial_dir/$i.out")
        bytes_end=$((bytes_end + size))
        i=$((i + 1))
    done

    printf 'received welcome:   %s/%s\n' "$ready_warm" "$count"
    printf 'received ticks:     %s/%s\n' "$tick_end" "$count"
    printf 'non-empty errs:     %s/%s\n' "$err_end" "$count"
    printf 'total bytes:        %s\n' "$bytes_end"

    curl_pids=""
    sleep 1
    print_mem "after-sse-$count"
}

run_sse_churn() {
    count="$1"
    rounds="$2"
    duration="$3"
    trial_dir="$tmp_dir/sse-churn-$count"
    mkdir -p "$trial_dir"

    printf '\n== sse churn: %s connections x %s rounds ==\n' "$count" "$rounds"
    print_mem "before-sse-churn"

    round=1
    total_ok=0
    total=$((count * rounds))
    while [ "$round" -le "$rounds" ]; do
        round_dir="$trial_dir/round-$round"
        mkdir -p "$round_dir"
        i=1
        while [ "$i" -le "$count" ]; do
            curl -N -sS --max-time "$duration" "http://127.0.0.1:$PORT/events" >"$round_dir/$i.out" 2>"$round_dir/$i.err" &
            printf '%s\n' "$!" >"$round_dir/$i.pid"
            i=$((i + 1))
        done
        i=1
        while [ "$i" -le "$count" ]; do
            pid=$(cat "$round_dir/$i.pid")
            wait "$pid" 2>/dev/null || true
            if grep -q "event: tick" "$round_dir/$i.out" 2>/dev/null; then
                total_ok=$((total_ok + 1))
            fi
            i=$((i + 1))
        done
        print_mem "after-sse-churn-round-$round"
        round=$((round + 1))
    done

    printf 'connections with ticks: %s/%s\n' "$total_ok" "$total"
    sleep 1
    print_mem "after-sse-churn"
}

for count in $SSE_COUNTS; do
    run_sse_trial "$count"
done

run_sse_churn "$SSE_CHURN_COUNT" "$SSE_CHURN_ROUNDS" "$SSE_CHURN_DURATION"

printf '\nserver log: %s\n' "$tmp_dir/server.log"
