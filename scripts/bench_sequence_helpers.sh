#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BASE_REF=${BASE_REF:-HEAD}
BASE_LABEL=$(printf '%s' "$BASE_REF" | tr '/:' '__')

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

current_bin="$tmp_dir/odinl-current"
base_dir="$tmp_dir/base"
base_bin="$tmp_dir/odinl-base"

printf 'building current compiler\n'
odin build "$ROOT/cmd/odinl" -out:"$current_bin"

printf 'building base compiler from %s\n' "$BASE_REF"
mkdir -p "$base_dir"
git -C "$ROOT" archive "$BASE_REF" | tar -x -C "$base_dir"
odin build "$base_dir/cmd/odinl" -out:"$base_bin"

run_bench() {
    label=$1
    compiler=$2
    generated="$tmp_dir/$label.odin"
    exe="$tmp_dir/$label"

    "$compiler" "$ROOT/benchmarks/sequence_helpers.odinl" -o "$generated"
    odin build "$generated" -file -o:speed -out:"$exe"
    printf '\n== %s ==\n' "$label"
    "$exe"
}

run_bench "base-$BASE_LABEL" "$base_bin"
run_bench "current" "$current_bin"

direct_exe="$tmp_dir/direct-odin"
odin build "$ROOT/benchmarks/sequence_helpers_direct.odin" -file -o:speed -out:"$direct_exe"
printf '\n== direct-odin ==\n'
"$direct_exe"
