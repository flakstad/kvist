#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

compiler="$tmp_dir/kvist-current"
generated="$tmp_dir/destructuring_helpers.odin"
current_exe="$tmp_dir/destructuring-current"
direct_exe="$tmp_dir/destructuring-direct"

printf 'building current compiler\n'
odin build "$ROOT/cmd/kvist" -out:"$compiler"

"$compiler" "$ROOT/benchmarks/destructuring_helpers.kvist" -o "$generated"
odin build "$generated" -file -o:speed -out:"$current_exe"
printf '\n== current-kvist ==\n'
"$current_exe"

odin build "$ROOT/benchmarks/destructuring_helpers_direct.odin" -file -o:speed -out:"$direct_exe"
printf '\n== direct-odin ==\n'
"$direct_exe"
