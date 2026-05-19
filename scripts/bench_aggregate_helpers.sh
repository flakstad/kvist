#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

compiler="$tmp_dir/odinl-current"
generated="$tmp_dir/aggregate_helpers.odin"
current_exe="$tmp_dir/aggregate-current"
direct_exe="$tmp_dir/aggregate-direct"

printf 'building current compiler\n'
odin build "$ROOT/cmd/odinl" -out:"$compiler"

"$compiler" "$ROOT/benchmarks/aggregate_helpers.odinl" -o "$generated"
odin build "$generated" -file -o:speed -out:"$current_exe"
printf '\n== current-odinl ==\n'
"$current_exe"

odin build "$ROOT/benchmarks/aggregate_helpers_direct.odin" -file -o:speed -out:"$direct_exe"
printf '\n== direct-odin ==\n'
"$direct_exe"
