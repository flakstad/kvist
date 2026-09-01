#!/usr/bin/env sh

set -u

compiler=${KVIST_PBT_COMPILER_REAL:-}
if [ -z "$compiler" ]; then
    printf 'KVIST_PBT_COMPILER_REAL is not set\n' >&2
    exit 2
fi

retry_dir=$(mktemp -d)
stdout_file="$retry_dir/stdout"
stderr_file="$retry_dir/stderr"
trap 'rm -rf "$retry_dir"' EXIT INT TERM

run_compiler() {
    "$compiler" "$@" >"$stdout_file" 2>"$stderr_file"
}

forward_output() {
    if [ -s "$stdout_file" ]; then
        sed -n '1,$p' "$stdout_file"
    fi
    if [ -s "$stderr_file" ]; then
        sed -n '1,$p' "$stderr_file" >&2
    fi
}

attempt=1
max_attempts=32
while :; do
    run_compiler "$@"
    status=$?
    if [ "$status" -eq 0 ]; then
        forward_output
        exit 0
    fi

    if [ "$attempt" -ge "$max_attempts" ] ||
       [ "$status" -ne 11 ] ||
       ! grep -F 'src/check_type.cpp(598): Assertion Failure: `tuple != nullptr` Queue($T=string)' "$stderr_file" >/dev/null; then
        break
    fi

    attempt=$((attempt + 1))
done

forward_output
exit "$status"
