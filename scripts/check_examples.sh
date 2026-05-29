#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

odin build cmd/kvist

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

for input in examples/*.kvist; do
    name=$(basename "$input" .kvist)
    output="$tmp_dir/$name.odin"
    map="$tmp_dir/$name.map"

    printf 'checking %s\n' "$input"
    ./kvist "$input" -o "$output" --map "$map"
    odin check "$output" -file
done

printf 'checked all examples\n'
