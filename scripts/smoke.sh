#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

run() {
    attempt=1
    while :; do
        "$@" && return 0
        status=$?
        if [ "$attempt" -ge 2 ]; then
            return "$status"
        fi
        printf 'retrying after exit %s: %s\n' "$status" "$*" >&2
        attempt=$((attempt + 1))
    done
}

capture() {
    output="$tmp_dir/capture.out"
    attempt=1
    while :; do
        if "$@" >"$output"; then
            cat "$output"
            return 0
        fi
        status=$?
        if [ "$attempt" -ge 2 ]; then
            cat "$output"
            return "$status"
        fi
        printf 'retrying after exit %s: %s\n' "$status" "$*" >&2
        attempt=$((attempt + 1))
    done
}

assert_eq() {
    expected=$1
    actual=$2
    label=$3
    if [ "$actual" != "$expected" ]; then
        printf 'failed: %s\nexpected: %s\nactual: %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

run odin build cmd/kvist

run ./kvist check examples/language/hello.kvist
assert_eq "hello from kvist" "$(capture ./kvist run examples/language/hello.kvist)" "hello"
assert_eq "18" "$(capture ./kvist run examples/collections/package-tour.kvist)" "package tour"
assert_eq "112" "$(capture ./kvist run examples/collections/log-source.kvist)" "log source"

run ./kvist doc examples/collections/log-source.kvist log-lines >/dev/null
run ./kvist lookup examples/collections/log-source.kvist log-lines >/dev/null
run ./kvist complete examples/collections/log-source.kvist log >/dev/null

printf 'smoke ok\n'
