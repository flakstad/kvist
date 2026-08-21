#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PBT_ROOT=${KVIST_PBT_ROOT:-"$ROOT/../pbt"}
ODIN_BIN=${KVIST_ODIN_BIN:-odin}

if [ ! -d "$PBT_ROOT/pbt" ]; then
    printf 'pbt package not found under %s/pbt\n' "$PBT_ROOT" >&2
    printf 'Place pbt next to Kvist as ../pbt or set KVIST_PBT_ROOT.\n' >&2
    exit 1
fi

cache_key=$(
    {
        printf '%s\n' "$ROOT"
        printf '%s\n' "$PBT_ROOT"
        "$ODIN_BIN" version
    } | cksum | awk '{print $1}'
)
cache_base=${KVIST_PBT_CACHE_DIR:-"$ROOT/tmp/pbt-cache"}
cache_dir="$cache_base/$cache_key"
mkdir -p "$cache_dir"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
runner="$cache_dir/kvist-pbt-compiler"
kvist_bin=${KVIST_PBT_COMPILER:-"$cache_dir/kvist"}
compiler_runner="$ROOT/scripts/pbt_compiler_retry.sh"
source_file=${KVIST_PBT_COMPILER_EXPRESSION_SOURCE:-"$ROOT/tests/pbt/targets/compiler_expressions.kvist"}
string_source_file=${KVIST_PBT_COMPILER_STRING_SOURCE:-"$ROOT/tests/pbt/targets/compiler_strings.kvist"}

artifact_stale() {
    artifact=$1
    shift
    if [ "${KVIST_PBT_REBUILD:-}" = "1" ] || [ ! -x "$artifact" ]; then
        return 0
    fi
    for source_path do
        newer=$(find "$source_path" \
            \( -type d -o \( -type f \( -name '*.odin' -o -name '*.kvist' \) \) \) \
            -newer "$artifact" -print -quit)
        if [ -n "$newer" ]; then
            return 0
        fi
    done
    return 1
}

if [ -z "${KVIST_PBT_COMPILER:-}" ] && \
   artifact_stale "$kvist_bin" "$ROOT/src/cli/kvist" "$ROOT/src/odin"; then
    temporary="$tmp_dir/kvist"
    "$ODIN_BIN" build "$ROOT/src/cli/kvist" -o:speed -out:"$temporary"
    mv "$temporary" "$kvist_bin"
fi

if artifact_stale "$runner" "$ROOT/tests/pbt/compiler" "$ROOT/src/odin/kvist" "$PBT_ROOT/pbt"; then
    temporary="$tmp_dir/kvist-pbt-compiler"
    "$ODIN_BIN" build "$ROOT/tests/pbt/compiler" \
        -collection:pbt="$PBT_ROOT" \
        -out:"$temporary"
    mv "$temporary" "$runner"
fi

KVIST_PBT_COMPILER_REAL="$kvist_bin" \
KVIST_PBT_COMPILER="$compiler_runner" \
KVIST_PBT_COMPILER_EXPRESSION_SOURCE="$source_file" \
KVIST_PBT_COMPILER_STRING_SOURCE="$string_source_file" \
KVIST_ROOT="$ROOT/src/kvist" \
    "$runner" "$@"
