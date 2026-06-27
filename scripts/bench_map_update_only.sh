#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

compiler="$tmp_dir/kvist-current"
generated="$tmp_dir/map_update_only.odin"
current_exe="$tmp_dir/map-current"
direct_exe="$tmp_dir/map-direct"

printf 'building current compiler\n'
odin build "$ROOT/cmd/kvist" -out:"$compiler"

"$compiler" "$ROOT/benchmarks/map_update_only.kvist" -o "$generated"
odin build "$generated" -file -o:speed -out:"$current_exe"
printf '\n== current-kvist ==\n'
"$current_exe"

odin build "$ROOT/benchmarks/map_update_only_direct.odin" -file -o:speed -out:"$direct_exe"
printf '\n== direct-odin ==\n'
"$direct_exe"
