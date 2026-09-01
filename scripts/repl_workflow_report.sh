#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <context.kvist> <requests.jsonl|->" >&2
    exit 2
fi

context_path=$1
requests_path=$2
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

if [ "$requests_path" = "-" ]; then
    requests_path="$tmp_dir/requests.jsonl"
    awk '{print}' >"$requests_path"
fi

if [ ! -f "$context_path" ]; then
    echo "REPL workflow context does not exist: $context_path" >&2
    exit 2
fi
if [ ! -f "$requests_path" ]; then
    echo "REPL workflow transcript does not exist: $requests_path" >&2
    exit 2
fi

if [ "${KVIST_WORKFLOW_COMPILER:-}" ]; then
    compiler=$KVIST_WORKFLOW_COMPILER
else
    compiler="$tmp_dir/kvist"
    odin build "$ROOT/src/cli/kvist" -o:speed -out:"$compiler"
fi

kvist_root=${KVIST_ROOT:-"$ROOT/src/kvist"}
modes=${KVIST_WORKFLOW_MODES:-"auto native-adapter native-reuse native"}
oracle_mode=${KVIST_WORKFLOW_ORACLE_MODE:-native}
oracle_present=false

for mode in $modes; do
    case "$mode" in
        auto|resident|native-adapter|native-reuse|native) ;;
        *)
            echo "unsupported REPL workflow execution mode: $mode" >&2
            exit 2
            ;;
    esac
    if [ "$mode" = "$oracle_mode" ]; then
        oracle_present=true
    fi
done
if [ "$oracle_present" != true ]; then
    echo "workflow modes must include oracle mode: $oracle_mode" >&2
    exit 2
fi

for mode in $modes; do
    events="$tmp_dir/$mode.events.jsonl"
    stderr="$tmp_dir/$mode.stderr"
    if ! KVIST_NO_COMPILE_CACHE="${KVIST_WORKFLOW_NO_COMPILE_CACHE:-1}" \
        KVIST_ROOT="$kvist_root" \
        "$compiler" repl "$context_path" \
            --execution "$mode" --protocol jsonl \
            <"$requests_path" >"$events" 2>"$stderr"; then
        echo "$mode REPL workflow failed" >&2
        sed -n '1,120p' "$stderr" >&2
        exit 1
    fi
    if [ -s "$stderr" ]; then
        echo "$mode REPL workflow wrote unexpected stderr" >&2
        sed -n '1,120p' "$stderr" >&2
        exit 1
    fi
    if [ "${KVIST_WORKFLOW_ALLOW_FAILURES:-0}" != "1" ] &&
        grep -q '"kind":"complete","success":false' "$events"; then
        echo "$mode REPL workflow contains a failed request" >&2
        grep '"kind":"complete","success":false' "$events" >&2
        exit 1
    fi
done

semantic_projection() {
    awk '
    /"kind":"output"/ ||
    /"kind":"stream-output"/ ||
    /"kind":"diagnostics"/ ||
    /"kind":"aborted"/ ||
    /"kind":"complete"/ {
        line = $0
        gsub(/,"native_cache_hit":(true|false)/, "", line)
        gsub(/,"frontend_cache_hit":(true|false)/, "", line)
        gsub(/,"execution_path":"[^"]*"/, "", line)
        print line
    }
    ' "$1"
}

oracle_semantics="$tmp_dir/$oracle_mode.semantics.jsonl"
semantic_projection "$tmp_dir/$oracle_mode.events.jsonl" >"$oracle_semantics"
for mode in $modes; do
    semantics="$tmp_dir/$mode.semantics.jsonl"
    semantic_projection "$tmp_dir/$mode.events.jsonl" >"$semantics"
    if ! cmp -s "$oracle_semantics" "$semantics"; then
        echo "semantic parity: FAILED ($mode vs $oracle_mode)" >&2
        diff -u "$oracle_semantics" "$semantics" >&2 || true
        exit 1
    fi
done

timing_projection() {
    awk '
    function text_field(line, key,    needle, rest) {
        needle = "\"" key "\":\""
        if (index(line, needle) == 0) return ""
        rest = substr(line, index(line, needle) + length(needle))
        sub(/\".*/, "", rest)
        return rest
    }
    function phase_ms(line, phase,    needle, rest) {
        needle = "\"phase\":\"" phase "\",\"elapsed_ns\":"
        if (index(line, needle) == 0) return 0
        rest = substr(line, index(line, needle) + length(needle))
        sub(/[^0-9].*/, "", rest)
        return (rest + 0) / 1000000.0
    }
    /"kind":"timings"/ {
        printf "%s\t%s\t%.3f\n",
            text_field($0, "id"),
            text_field($0, "execution_path"),
            phase_ms($0, "controller-total")
    }
    ' "$1"
}

for mode in $modes; do
    timing_projection "$tmp_dir/$mode.events.jsonl" >"$tmp_dir/$mode.timings.tsv"
done

echo "semantic parity: ok (oracle: $oracle_mode)"
printf "mode\tid\texecution_path\tcontroller_ms\toracle_over_mode\n"
for mode in $modes; do
    paste "$tmp_dir/$mode.timings.tsv" "$tmp_dir/$oracle_mode.timings.tsv" |
        awk -F '\t' -v mode="$mode" '
        {
            if ($1 != $4) {
                printf "timing event mismatch: %s != %s\n", $1, $4 > "/dev/stderr"
                exit 1
            }
            speedup = $3 > 0 ? $6 / $3 : 0
            printf "%s\t%s\t%s\t%.3f\t%.1fx\n",
                mode, $1, $2, $3, speedup
        }
        '
done

echo
echo "session totals:"
printf "mode\tcontroller_ms\toracle_over_mode\n"
oracle_total=$(awk -F '\t' '{ total += $3 } END { printf "%.6f", total }' \
    "$tmp_dir/$oracle_mode.timings.tsv")
for mode in $modes; do
    awk -F '\t' -v mode="$mode" -v oracle_total="$oracle_total" '
    { total += $3 }
    END {
        speedup = total > 0 ? oracle_total / total : 0
        printf "%s\t%.3f\t%.1fx\n", mode, total, speedup
    }
    ' "$tmp_dir/$mode.timings.tsv"
done

echo
echo "execution paths:"
printf "mode\tcount\texecution_path\n"
for mode in $modes; do
    awk -F '\t' -v mode="$mode" '
    { count[$2] += 1 }
    END {
        for (path in count) {
            printf "%s\t%d\t%s\n", mode, count[path], path
        }
    }
    ' "$tmp_dir/$mode.timings.tsv" | sort -k3
done
