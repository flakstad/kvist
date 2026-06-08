#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

odin build cmd/kvist

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

find examples/collections \
     examples/interop \
     examples/language \
     examples/packages \
     examples/visual \
     examples/web \
     -name '*.kvist' \
     ! -path 'examples/visual/simple-game/*' \
     -print |
sort |
while IFS= read -r input; do
    name=$(basename "$input" .kvist)
    output="$tmp_dir/$name.odin"
    map="$tmp_dir/$name.map"

    printf 'checking %s\n' "$input"
    ./kvist "$input" -o "$output" --map "$map"
    if grep -Eq '^package tests$' "$output"; then
        odin test "$output" -file
    else
        odin check "$output" -file
    fi
done

printf 'checked all examples\n'
