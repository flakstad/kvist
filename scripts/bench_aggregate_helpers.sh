#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

compiler="$tmp_dir/kvist-current"
generated="$tmp_dir/aggregate_helpers.odin"
current_exe="$tmp_dir/aggregate-current"
direct_exe="$tmp_dir/aggregate-direct"

printf 'building current compiler\n'
odin build "$ROOT/cmd/kvist" -out:"$compiler"

"$compiler" "$ROOT/benchmarks/aggregate_helpers.kvist" -o "$generated"
odin build "$generated" -file -o:speed -out:"$current_exe"
printf '\n== current-kvist ==\n'
"$current_exe"

odin build "$ROOT/benchmarks/aggregate_helpers_direct.odin" -file -o:speed -out:"$direct_exe"
printf '\n== direct-odin ==\n'
"$direct_exe"
