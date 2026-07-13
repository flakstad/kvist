#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

odin build src/cli/kvist

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
    if [ "$input" = "examples/collections/ownership-warnings.kvist" ]; then
        warnings="$tmp_dir/ownership-warnings.txt"
        ./kvist "$input" -o "$output" --map "$map" 2>"$warnings"
        for expected in \
            'owned result from arr.range is discarded' \
            'owned local xs is never deleted or returned' \
            'owned local xs is overwritten before cleanup' \
            'owned local xs is used after ownership transfer' \
            'borrowed value escapes owner xs'
        do
            if ! grep -q "$expected" "$warnings"; then
                printf 'failed: missing expected ownership warning: %s\n' "$expected" >&2
                cat "$warnings" >&2
                exit 1
            fi
        done
        if [ "$(grep -c ': warning:' "$warnings")" -ne 5 ]; then
            printf 'failed: ownership warning fixture emitted unexpected warnings\n' >&2
            cat "$warnings" >&2
            exit 1
        fi
    else
        ./kvist "$input" -o "$output" --map "$map"
    fi
    if grep -Eq '^package tests$' "$output"; then
        run_odin odin test "$output" -file -define:ODIN_TEST_THREADS=1
    else
        run_odin odin check "$output" -file -no-entry-point
    fi
done

printf 'checked all examples\n'
