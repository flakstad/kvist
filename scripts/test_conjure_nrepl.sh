#!/usr/bin/env sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONJURE_COMMIT=${CONJURE_COMMIT:-84c739c753bd07c006849d10ebce1863dd41af7f}
CONJURE_REPOSITORY=${CONJURE_REPOSITORY:-https://github.com/Olical/conjure.git}

for command in git nvim odin; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'missing required command: %s\n' "$command" >&2
        exit 1
    fi
done

tmp_dir=$(mktemp -d)
server_pid=
cleanup() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

conjure_dir="$tmp_dir/conjure"
git init -q "$conjure_dir"
git -C "$conjure_dir" remote add origin "$CONJURE_REPOSITORY"
git -C "$conjure_dir" fetch -q --depth 1 origin "$CONJURE_COMMIT"
git -C "$conjure_dir" checkout -q --detach FETCH_HEAD

kvist_binary="$tmp_dir/kvist"
odin build "$ROOT/src/cli/kvist" -out:"$kvist_binary"
port_file="$tmp_dir/nrepl-port"
KVIST_ROOT="$ROOT/src/kvist" "$kvist_binary" nrepl \
    "$ROOT/tests/integration/conjure/load-file.kvist" \
    --port 0 --port-file "$port_file" --once \
    >"$tmp_dir/server.out" 2>"$tmp_dir/server.err" &
server_pid=$!

attempt=0
while [ ! -s "$port_file" ]; do
    if ! kill -0 "$server_pid" 2>/dev/null; then
        printf 'Kvist nREPL exited before Conjure connected\n' >&2
        sed -n '1,200p' "$tmp_dir/server.err" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 300 ]; then
        printf 'timed out waiting for the Kvist nREPL port file\n' >&2
        exit 1
    fi
    sleep 0.1
done

export KVIST_CONJURE_ROOT="$conjure_dir"
export KVIST_CONJURE_PORT
KVIST_CONJURE_PORT=$(tr -d '[:space:]' <"$port_file")
export KVIST_CONJURE_SOURCE="$ROOT/tests/integration/conjure/load-file.kvist"

if ! (cd "$tmp_dir" && nvim --headless -u NONE -i NONE \
    -l "$ROOT/tests/integration/conjure/kvist-conjure-test.lua"); then
    printf 'Kvist nREPL stdout:\n' >&2
    sed -n '1,200p' "$tmp_dir/server.out" >&2
    printf 'Kvist nREPL stderr:\n' >&2
    sed -n '1,200p' "$tmp_dir/server.err" >&2
    exit 1
fi

wait "$server_pid"
server_pid=
printf 'conjure nrepl: ok (Conjure %s)\n' "$CONJURE_COMMIT"
