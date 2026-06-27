#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

odin build cmd/kvist

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

run_odin() {
    attempt=1
    while :; do
        "$@" && return 0
        status=$?
        if [ "$attempt" -ge 3 ]; then
            return "$status"
        fi
        printf 'retrying after odin exited with %s: %s\n' "$status" "$*" >&2
        attempt=$((attempt + 1))
    done
}

find examples/collections \
     examples/coverage \
     examples/interop \
     examples/language \
     examples/packages \
     examples/visual \
     examples/web \
     -name '*.kvist' \
     ! -path 'examples/visual/simple-game/*' \
     ! -path 'examples/coverage/packages/order-independent/*' \
     -print |
sort |
while IFS= read -r input; do
    name=$(basename "$input" .kvist)
    output="$tmp_dir/$name.odin"
    map="$tmp_dir/$name.map"

    printf 'checking %s\n' "$input"
    ./kvist "$input" -o "$output" --map "$map"
    if grep -Eq '^package tests$' "$output"; then
        run_odin odin test "$output" -file -define:ODIN_TEST_THREADS=1
    else
        run_odin odin check "$output" -file -no-entry-point
    fi
done

printf 'checked all examples\n'
