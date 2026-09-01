#!/usr/bin/env sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export KVIST_ROOT="$ROOT/src/kvist"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

compiler="$tmp_dir/kvist"
generated="$tmp_dir/data-collections.odin"
executable="$tmp_dir/data-collections"

odin build "$ROOT/src/cli/kvist" -o:speed -out:"$compiler"
"$compiler" "$ROOT/benchmarks/data_collections.kvist" -o "$generated"
odin build "$generated" -file -o:speed -out:"$executable"
"$executable"
