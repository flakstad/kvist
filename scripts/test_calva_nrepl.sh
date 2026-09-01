#!/usr/bin/env sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CALVA_COMMIT=${CALVA_COMMIT:-6583b2d74e048a7e84c29ee278efed107079273e}
CALVA_REPOSITORY=${CALVA_REPOSITORY:-https://github.com/BetterThanTomorrow/calva.git}
CALVA_E2E_VSCODE_VERSION=${CALVA_E2E_VSCODE_VERSION:-1.135.0}
export CALVA_E2E_VSCODE_VERSION

for command in git node npm odin; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'missing required command: %s\n' "$command" >&2
        exit 1
    fi
done

tmp_dir=$(mktemp -d)
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

calva_dir="$tmp_dir/calva"
git init -q "$calva_dir"
git -C "$calva_dir" remote add origin "$CALVA_REPOSITORY"
git -C "$calva_dir" fetch -q --depth 1 origin "$CALVA_COMMIT"
git -C "$calva_dir" checkout -q --detach FETCH_HEAD

cp "$ROOT/tests/integration/calva/kvist-nrepl-test.ts" \
    "$calva_dir/src/extension-test/e2e/suite/kvist-nrepl-test.ts"
cp "$ROOT/tests/integration/calva/run-kvist-e2e.cjs" \
    "$calva_dir/run-kvist-e2e.cjs"

npm ci --prefix "$calva_dir"
npm run --prefix "$calva_dir" compile

kvist_binary="$tmp_dir/kvist"
if [ "${OS:-}" = "Windows_NT" ]; then
    kvist_binary="$tmp_dir/kvist.exe"
fi
odin build "$ROOT/src/cli/kvist" -out:"$kvist_binary"

export KVIST_E2E_BINARY="$kvist_binary"
export KVIST_E2E_ROOT="$ROOT/src/kvist"

if [ "$(uname -s 2>/dev/null || true)" = "Linux" ] && command -v xvfb-run >/dev/null 2>&1; then
    (cd "$calva_dir" && xvfb-run -a node run-kvist-e2e.cjs)
else
    (cd "$calva_dir" && node run-kvist-e2e.cjs)
fi

printf 'calva nrepl: ok (Calva %s, VS Code %s)\n' \
    "$CALVA_COMMIT" "$CALVA_E2E_VSCODE_VERSION"
