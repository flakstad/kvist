#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CIDER_COMMIT=${CIDER_COMMIT:-60623abc533fe7e818730fbbec9277ec0dc6c916}
CIDER_REPOSITORY=${CIDER_REPOSITORY:-https://github.com/clojure-emacs/cider.git}
ELDEV_COMMIT=${ELDEV_COMMIT:-92a46b48793e561b00189a06014df0d7bbeed3be}
ELDEV_REPOSITORY=${ELDEV_REPOSITORY:-https://github.com/emacs-eldev/eldev.git}
EMACS=${EMACS:-}

if [ -z "$EMACS" ]; then
    if command -v emacs >/dev/null 2>&1; then
        EMACS=$(command -v emacs)
    elif [ -x /Applications/Emacs.app/Contents/MacOS/Emacs ]; then
        EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
    else
        printf 'missing required command: emacs\n' >&2
        exit 1
    fi
fi

for command in git odin; do
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

fetch_commit() {
    repository=$1
    commit=$2
    destination=$3
    git init -q "$destination"
    git -C "$destination" remote add origin "$repository"
    git -C "$destination" fetch -q --depth 1 origin "$commit"
    git -C "$destination" checkout -q --detach FETCH_HEAD
}

cider_dir="$tmp_dir/cider"
eldev_dir="$tmp_dir/eldev"
fetch_commit "$CIDER_REPOSITORY" "$CIDER_COMMIT" "$cider_dir"
fetch_commit "$ELDEV_REPOSITORY" "$ELDEV_COMMIT" "$eldev_dir"

kvist_binary="$tmp_dir/kvist"
odin build "$ROOT/src/cli/kvist" -out:"$kvist_binary"
port_file="$tmp_dir/nrepl-port"
KVIST_ROOT="$ROOT/src/kvist" "$kvist_binary" nrepl \
    "$ROOT/tests/integration/cider/source-buffer.kvist" \
    --port 0 --port-file "$port_file" --once \
    >"$tmp_dir/server.out" 2>"$tmp_dir/server.err" &
server_pid=$!

attempt=0
while [ ! -s "$port_file" ]; do
    if ! kill -0 "$server_pid" 2>/dev/null; then
        printf 'Kvist nREPL exited before CIDER connected\n' >&2
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

export ELDEV_EMACS="$EMACS"
export ELDEV_DIR="$tmp_dir/eldev-state"
export KVIST_CIDER_PORT
KVIST_CIDER_PORT=$(tr -d '[:space:]' <"$port_file")
export KVIST_CIDER_PROJECT_DIR="$ROOT"
export KVIST_CIDER_SOURCE="$ROOT/tests/integration/cider/source-buffer.kvist"
export KVIST_CIDER_EMACS_DIR="$ROOT/emacs"

(cd "$cider_dir" && "$eldev_dir/bin/eldev" -q prepare)
(cd "$cider_dir" && "$eldev_dir/bin/eldev" -q exec \
    -f "$ROOT/tests/integration/cider/kvist-cider-test.el")

wait "$server_pid"
server_pid=
printf 'cider nrepl: ok (CIDER %s)\n' "$CIDER_COMMIT"
