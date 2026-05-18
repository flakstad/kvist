#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

odin build cmd/odinl

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

assert_eq() {
    expected=$1
    actual=$2
    label=$3
    if [ "$actual" != "$expected" ]; then
        printf 'failed: %s\nexpected: %s\nactual: %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_file_nonempty() {
    path=$1
    label=$2
    if [ ! -s "$path" ]; then
        printf 'failed: %s did not create a non-empty file at %s\n' "$label" "$path" >&2
        exit 1
    fi
}

printf 'tooling: compile command\n'
./odinl compile examples/hello.odinl -o "$tmp_dir/hello.odin" --map "$tmp_dir/hello.map"
assert_file_nonempty "$tmp_dir/hello.odin" "compile output"
assert_file_nonempty "$tmp_dir/hello.map" "compile source map"
odin check "$tmp_dir/hello.odin" -file

printf 'tooling: check command\n'
./odinl check examples/hello.odinl --generated "$tmp_dir/check.odin"
assert_file_nonempty "$tmp_dir/check.odin" "check generated output"

printf 'tooling: check diagnostic mapping\n'
cat > "$tmp_dir/bad.odinl" <<'EOF'
(package main)
(import "core:fmt")

(proc main []
  (let [x: int "bad"]
    (fmt.println x)))
EOF
if ./odinl check "$tmp_dir/bad.odinl" >"$tmp_dir/bad-check.out" 2>"$tmp_dir/bad-check.err"; then
    printf 'failed: bad check unexpectedly succeeded\n' >&2
    exit 1
fi
if ! grep -q "$tmp_dir/bad.odinl:4:1 Error: Cannot convert" "$tmp_dir/bad-check.err"; then
    printf 'failed: bad check diagnostic did not map back to .odinl\n' >&2
    cat "$tmp_dir/bad-check.err" >&2
    exit 1
fi

printf 'tooling: run command\n'
run_output=$(./odinl run examples/hello.odinl)
assert_eq "hello from odinl" "$run_output" "run output"

printf 'tooling: eval command\n'
eval_output=$(./odinl eval examples/higher-order.odinl '(reduce-int (new [dynamic]int [1 2 3]) 0 add)' --generated "$tmp_dir/eval.odin")
assert_eq "6" "$eval_output" "eval output"
assert_file_nonempty "$tmp_dir/eval.odin" "eval generated output"

printf 'tooling: eval check command\n'
./odinl eval examples/higher-order.odinl '(reduce-int (new [dynamic]int [1 2 3]) 0 add)' --check

printf 'tooling: legacy eval compile path\n'
./odinl examples/higher-order.odinl --eval '(reduce-int (new [dynamic]int [1 2 3]) 0 add)' -o "$tmp_dir/legacy-eval.odin"
legacy_output=$(odin run "$tmp_dir/legacy-eval.odin" -file)
assert_eq "6" "$legacy_output" "legacy eval output"

printf 'tooling: eval diagnostics\n'
if ./odinl eval examples/higher-order.odinl '(not 1 2)' >"$tmp_dir/bad.out" 2>"$tmp_dir/bad.err"; then
    printf 'failed: bad eval unexpectedly succeeded\n' >&2
    exit 1
fi
if ! grep -q 'examples/higher-order.odinl:<eval>:1:1: not expects one argument' "$tmp_dir/bad.err"; then
    printf 'failed: bad eval diagnostic did not point at <eval>\n' >&2
    cat "$tmp_dir/bad.err" >&2
    exit 1
fi

if command -v emacs >/dev/null 2>&1; then
    printf 'tooling: emacs byte compile\n'
    emacs -Q --batch --eval \
        '(progn
           (defvar clojure-mode-map (make-sparse-keymap))
           (define-derived-mode clojure-mode prog-mode "Clojure")
           (defun clojure--put-indentation-spec (&rest _args) nil)
           (provide (quote clojure-mode))
           (add-to-list (quote load-path) "emacs")
           (byte-compile-file "emacs/odinl-mode.el")
           (load-file "emacs/odinl-mode.el")
           (byte-compile-file "emacs/odinl-eval.el"))'
    rm -f emacs/odinl-mode.elc emacs/odinl-eval.elc
else
    printf 'tooling: emacs not found, skipping byte compile\n'
fi

printf 'tooling integration ok\n'
