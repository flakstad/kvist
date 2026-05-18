#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

odin build cmd/odinl

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

for input in examples/*.odinl; do
    name=$(basename "$input" .odinl)
    output="$tmp_dir/$name.odin"
    map="$tmp_dir/$name.map"

    printf 'checking %s\n' "$input"
    ./odinl "$input" -o "$output" --map "$map"
    odin check "$output" -file
done

printf 'checked all examples\n'
