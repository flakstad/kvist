#!/usr/bin/env sh

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
runner="$cache_dir/kvist-pbt"
kvist_bin="$cache_dir/kvist"
edn_target=${KVIST_PBT_EDN_TARGET:-"$cache_dir/kvist-pbt-edn-target"}
data_map_target=${KVIST_PBT_DATA_MAP_TARGET:-"$cache_dir/kvist-pbt-data-map-target"}
data_nested_target=${KVIST_PBT_DATA_NESTED_TARGET:-"$cache_dir/kvist-pbt-data-nested-target"}
data_sequence_target=${KVIST_PBT_DATA_SEQUENCE_TARGET:-"$cache_dir/kvist-pbt-data-sequence-target"}
set_target=${KVIST_PBT_SET_TARGET:-"$cache_dir/kvist-pbt-set-target"}
data_transform_target=${KVIST_PBT_DATA_TRANSFORM_TARGET:-"$cache_dir/kvist-pbt-data-transform-target"}
map_target=${KVIST_PBT_MAP_TARGET:-"$cache_dir/kvist-pbt-map-target"}
data_aggregate_target=${KVIST_PBT_DATA_AGGREGATE_TARGET:-"$cache_dir/kvist-pbt-data-aggregate-target"}
data_scan_target=${KVIST_PBT_DATA_SCAN_TARGET:-"$cache_dir/kvist-pbt-data-scan-target"}
data_map_transform_target=${KVIST_PBT_DATA_MAP_TRANSFORM_TARGET:-"$cache_dir/kvist-pbt-data-map-transform-target"}
data_set_target=${KVIST_PBT_DATA_SET_TARGET:-"$cache_dir/kvist-pbt-data-set-target"}
data_access_target=${KVIST_PBT_DATA_ACCESS_TARGET:-"$cache_dir/kvist-pbt-data-access-target"}
typed_decode_target=${KVIST_PBT_TYPED_DECODE_TARGET:-"$cache_dir/kvist-pbt-typed-decode-target"}

artifact_stale() {
    artifact=$1
    shift
    if [ "${KVIST_PBT_REBUILD:-}" = "1" ] || [ ! -x "$artifact" ]; then
        return 0
    fi
    for source_path do
        if [ ! -e "$source_path" ]; then
            return 0
        fi
        if [ -d "$source_path" ]; then
            newer=$(find "$source_path" \
                \( -type d -o \( -type f \( -name '*.odin' -o -name '*.kvist' \) \) \) \
                -newer "$artifact" -print -quit)
        else
            newer=$(find "$source_path" -newer "$artifact" -print -quit)
        fi
        if [ -n "$newer" ]; then
            return 0
        fi
    done
    return 1
}

build_target() {
    source_file=$1
    output_file=$2
    temporary="$tmp_dir/$(basename "$output_file")"
    KVIST_ROOT="$ROOT/src/kvist" "$kvist_bin" build \
        "$source_file" \
        --out "$temporary"
    mv "$temporary" "$output_file"
}

if [ -z "${KVIST_PBT_EDN_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_DATA_MAP_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_DATA_NESTED_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_DATA_SEQUENCE_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_SET_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_DATA_TRANSFORM_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_MAP_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_DATA_AGGREGATE_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_DATA_SCAN_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_DATA_MAP_TRANSFORM_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_DATA_SET_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_DATA_ACCESS_TARGET:-}" ] || \
   [ -z "${KVIST_PBT_TYPED_DECODE_TARGET:-}" ]; then
    if artifact_stale "$kvist_bin" "$ROOT/src/cli/kvist" "$ROOT/src/odin"; then
        temporary="$tmp_dir/kvist"
        "$ODIN_BIN" build "$ROOT/src/cli/kvist" -o:speed -out:"$temporary"
        mv "$temporary" "$kvist_bin"
    fi
fi

if [ -z "${KVIST_PBT_EDN_TARGET:-}" ] && \
   artifact_stale "$edn_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/edn_roundtrip.kvist"; then
    build_target "$ROOT/tests/pbt/targets/edn_roundtrip.kvist" "$edn_target"
fi

if [ -z "${KVIST_PBT_DATA_MAP_TARGET:-}" ] && \
   artifact_stale "$data_map_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/data_map_commands.kvist"; then
    build_target "$ROOT/tests/pbt/targets/data_map_commands.kvist" "$data_map_target"
fi

if [ -z "${KVIST_PBT_DATA_NESTED_TARGET:-}" ] && \
   artifact_stale "$data_nested_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/data_nested_commands.kvist"; then
    build_target "$ROOT/tests/pbt/targets/data_nested_commands.kvist" "$data_nested_target"
fi

if [ -z "${KVIST_PBT_DATA_SEQUENCE_TARGET:-}" ] && \
   artifact_stale "$data_sequence_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/data_sequence_commands.kvist"; then
    build_target "$ROOT/tests/pbt/targets/data_sequence_commands.kvist" "$data_sequence_target"
fi

if [ -z "${KVIST_PBT_SET_TARGET:-}" ] && \
   artifact_stale "$set_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/native_set_operations.kvist"; then
    build_target "$ROOT/tests/pbt/targets/native_set_operations.kvist" "$set_target"
fi

if [ -z "${KVIST_PBT_DATA_TRANSFORM_TARGET:-}" ] && \
   artifact_stale "$data_transform_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/data_transforms.kvist"; then
    build_target "$ROOT/tests/pbt/targets/data_transforms.kvist" "$data_transform_target"
fi

if [ -z "${KVIST_PBT_MAP_TARGET:-}" ] && \
   artifact_stale "$map_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/native_map_operations.kvist"; then
    build_target "$ROOT/tests/pbt/targets/native_map_operations.kvist" "$map_target"
fi

if [ -z "${KVIST_PBT_DATA_AGGREGATE_TARGET:-}" ] && \
   artifact_stale "$data_aggregate_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/data_aggregates.kvist"; then
    build_target "$ROOT/tests/pbt/targets/data_aggregates.kvist" "$data_aggregate_target"
fi

if [ -z "${KVIST_PBT_DATA_SCAN_TARGET:-}" ] && \
   artifact_stale "$data_scan_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/data_scans.kvist"; then
    build_target "$ROOT/tests/pbt/targets/data_scans.kvist" "$data_scan_target"
fi

if [ -z "${KVIST_PBT_DATA_MAP_TRANSFORM_TARGET:-}" ] && \
   artifact_stale "$data_map_transform_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/data_map_transforms.kvist"; then
    build_target "$ROOT/tests/pbt/targets/data_map_transforms.kvist" "$data_map_transform_target"
fi

if [ -z "${KVIST_PBT_DATA_SET_TARGET:-}" ] && \
   artifact_stale "$data_set_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/data_set_commands.kvist"; then
    build_target "$ROOT/tests/pbt/targets/data_set_commands.kvist" "$data_set_target"
fi

if [ -z "${KVIST_PBT_DATA_ACCESS_TARGET:-}" ] && \
   artifact_stale "$data_access_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/data_accessors.kvist"; then
    build_target "$ROOT/tests/pbt/targets/data_accessors.kvist" "$data_access_target"
fi

if [ -z "${KVIST_PBT_TYPED_DECODE_TARGET:-}" ] && \
   artifact_stale "$typed_decode_target" "$kvist_bin" "$ROOT/src/kvist" "$ROOT/tests/pbt/targets/typed_decode.kvist"; then
    build_target "$ROOT/tests/pbt/targets/typed_decode.kvist" "$typed_decode_target"
fi

if artifact_stale "$runner" "$ROOT/tests/pbt" "$ROOT/src/odin/kvist" "$PBT_ROOT/pbt"; then
    temporary="$tmp_dir/kvist-pbt"
    "$ODIN_BIN" build "$ROOT/tests/pbt" \
        -collection:pbt="$PBT_ROOT" \
        -out:"$temporary"
    mv "$temporary" "$runner"
fi

KVIST_PBT_EDN_TARGET="$edn_target" \
KVIST_PBT_DATA_MAP_TARGET="$data_map_target" \
KVIST_PBT_DATA_NESTED_TARGET="$data_nested_target" \
KVIST_PBT_DATA_SEQUENCE_TARGET="$data_sequence_target" \
KVIST_PBT_SET_TARGET="$set_target" \
KVIST_PBT_DATA_TRANSFORM_TARGET="$data_transform_target" \
KVIST_PBT_MAP_TARGET="$map_target" \
KVIST_PBT_DATA_AGGREGATE_TARGET="$data_aggregate_target" \
KVIST_PBT_DATA_SCAN_TARGET="$data_scan_target" \
KVIST_PBT_DATA_MAP_TRANSFORM_TARGET="$data_map_transform_target" \
KVIST_PBT_DATA_SET_TARGET="$data_set_target" \
KVIST_PBT_DATA_ACCESS_TARGET="$data_access_target" \
KVIST_PBT_TYPED_DECODE_TARGET="$typed_decode_target" \
    "$runner" "$@"
