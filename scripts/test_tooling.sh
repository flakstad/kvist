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

printf 'tooling: build command\n'
./odinl build examples/hello.odinl --generated "$tmp_dir/build.odin"
assert_file_nonempty "$tmp_dir/build.odin" "build generated output"

printf 'tooling: run command\n'
run_output=$(./odinl run examples/hello.odinl)
assert_eq "hello from odinl" "$run_output" "run output"

printf 'tooling: eval command\n'
eval_output=$(./odinl eval examples/higher-order.odinl '(reduce add 0 (new []int [1 2 3]))' --generated "$tmp_dir/eval.odin")
assert_eq "6" "$eval_output" "eval output"
assert_file_nonempty "$tmp_dir/eval.odin" "eval generated output"

printf 'tooling: expand command\n'
./odinl expand examples/data-literals.odinl '(temp-buffer-len)' -o "$tmp_dir/expand.odin"
assert_file_nonempty "$tmp_dir/expand.odin" "expand generated output"
if ! grep -q 'context.allocator = allocator' "$tmp_dir/expand.odin"; then
    printf 'failed: expand output did not include with-allocator lowering\n' >&2
    cat "$tmp_dir/expand.odin" >&2
    exit 1
fi
if ! grep -q 'fmt.println(temp_buffer_len())' "$tmp_dir/expand.odin"; then
    printf 'failed: expand output did not include eval print wrapper\n' >&2
    cat "$tmp_dir/expand.odin" >&2
    exit 1
fi
odin check "$tmp_dir/expand.odin" -file

printf 'tooling: eval main command\n'
main_eval_output=$(./odinl eval examples/hello.odinl '(main)')
assert_eq "hello from odinl" "$main_eval_output" "eval main output"

printf 'tooling: sequence example evals\n'
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(split-front-length)')" "split-front-length"
assert_eq "4" "$(./odinl eval examples/sequence-helpers.odinl '(first-kept-square)')" "first-kept-square"
assert_eq "45" "$(./odinl eval examples/sequence-helpers.odinl '(age-for-grace)')" "age-for-grace"
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(chunk-count)')" "chunk-count"
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(repeated-two-count)')" "repeated-two-count"
assert_eq "3" "$(./odinl eval examples/sequence-helpers.odinl '(indexed-name-count)')" "indexed-name-count"
assert_eq "3" "$(./odinl eval examples/sequence-helpers.odinl '(even-group-count)')" "even-group-count"
assert_eq "10" "$(./odinl eval examples/sequence-helpers.odinl '(range-total)')" "range-total"
assert_eq "3" "$(./odinl eval examples/sequence-helpers.odinl '(repeated-answer-count)')" "repeated-answer-count"
assert_eq "odin" "$(./odinl eval examples/sequence-helpers.odinl '(repeated-word-last)')" "repeated-word-last"
assert_eq "8" "$(./odinl eval examples/sequence-helpers.odinl '(iterated-last)')" "iterated-last"
assert_eq "9" "$(./odinl eval examples/sequence-helpers.odinl '(cycled-total)')" "cycled-total"
assert_eq "5" "$(./odinl eval examples/sequence-helpers.odinl '(counted-cycle)')" "counted-cycle"
assert_eq "13" "$(./odinl eval examples/sequence-helpers.odinl '(trimmed-sum)')" "trimmed-sum"
assert_eq "40" "$(./odinl eval examples/sequence-helpers.odinl '(rest-second-empty-score)')" "rest-second-empty-score"
assert_eq "4" "$(./odinl eval examples/sequence-helpers.odinl '(concat-reversed-first)')" "concat-reversed-first"
assert_eq "26" "$(./odinl eval examples/sequence-helpers.odinl '(interposed-total)')" "interposed-total"
assert_eq "33" "$(./odinl eval examples/sequence-helpers.odinl '(interleaved-total)')" "interleaved-total"
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(shuffled-first)')" "shuffled-first"
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(shuffled-in-place-first)')" "shuffled-in-place-first"
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(sorted-second)')" "sorted-second"
assert_eq "4" "$(./odinl eval examples/sequence-helpers.odinl '(descending-first)')" "descending-first"
assert_eq "1" "$(./odinl eval examples/sequence-helpers.odinl '(sorted-in-place-first)')" "sorted-in-place-first"
assert_eq "4" "$(./odinl eval examples/sequence-helpers.odinl '(reversed-in-place-first)')" "reversed-in-place-first"
assert_eq "4" "$(./odinl eval examples/sequence-helpers.odinl '(descending-in-place-first)')" "descending-in-place-first"
assert_eq "12" "$(./odinl eval examples/sequence-helpers.odinl '(doubled-in-place-total)')" "doubled-in-place-total"
assert_eq "3" "$(./odinl eval examples/sequence-helpers.odinl '(indexed-in-place-second)')" "indexed-in-place-second"
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(filtered-in-place-count)')" "filtered-in-place-count"
assert_eq "1" "$(./odinl eval examples/sequence-helpers.odinl '(removed-in-place-first)')" "removed-in-place-first"
assert_eq "4" "$(./odinl eval examples/sequence-helpers.odinl '(kept-in-place-first)')" "kept-in-place-first"
assert_eq "10" "$(./odinl eval examples/sequence-helpers.odinl '(appended-total)')" "appended-total"
assert_eq "6" "$(./odinl eval examples/sequence-helpers.odinl '(copied-total)')" "copied-total"
assert_eq "6" "$(./odinl eval examples/sequence-helpers.odinl '(distinct-total)')" "distinct-total"
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(first-per-parity-count)')" "first-per-parity-count"
assert_eq "1" "$(./odinl eval examples/sequence-helpers.odinl '(ragged-chunk-size)')" "ragged-chunk-size"
assert_eq "4" "$(./odinl eval examples/sequence-helpers.odinl '(run-count)')" "run-count"
assert_eq "15" "$(./odinl eval examples/sequence-helpers.odinl '(flattened-total)')" "flattened-total"
assert_eq "4" "$(./odinl eval examples/sequence-helpers.odinl '(threaded-first)')" "threaded-first"
assert_eq "/health" "$(./odinl eval examples/declarations.odinl '(endpoint-summary)')" "endpoint-summary"
assert_eq "404" "$(./odinl eval examples/declarations.odinl '(shorthand-status-code)')" "shorthand-status-code"
assert_eq "36" "$(./odinl eval examples/sequences.odinl '(age-for-ada)')" "age-for-ada"
assert_eq "3" "$(./odinl eval examples/sequences.odinl '(status-run-count)')" "status-run-count"
assert_eq "2" "$(./odinl eval examples/sequences.odinl '(active-status-group-count)')" "active-status-group-count"
assert_eq "2" "$(./odinl eval examples/data-literals.odinl '(temp-buffer-len)')" "temp-buffer-len"
assert_eq "-1" "$(./odinl eval examples/data-literals.odinl '(lookup-missing-default)')" "lookup-missing-default"
assert_eq "51" "$(./odinl eval examples/data-literals.odinl '(merged-lookup-total)')" "merged-lookup-total"
assert_eq "51" "$(./odinl eval examples/data-literals.odinl '(merge-in-place-total)')" "merge-in-place-total"
assert_eq "Lin" "$(./odinl eval examples/sequences.odinl '(youngest-user-name)')" "youngest-user-name"
assert_eq "Lin" "$(./odinl eval examples/sequences.odinl '(youngest-user-name-in-place)')" "youngest-user-name-in-place"

printf 'tooling: eval check command\n'
./odinl eval examples/higher-order.odinl '(reduce add 0 (new []int [1 2 3]))' --check

printf 'tooling: eval declaration form\n'
cat > "$tmp_dir/decl-eval.odinl" <<'EOF'
(package main)
(import "core:fmt")

(struct Greeting {
  :message string
})

(proc main []
  (fmt.println "hello"))
EOF
./odinl eval "$tmp_dir/decl-eval.odinl" '(struct Greeting { :message string })' --check
./odinl eval "$tmp_dir/decl-eval.odinl" '(import "core:fmt")' --check
./odinl eval "$tmp_dir/decl-eval.odinl" '(proc main [] (fmt.println "hello"))' --check

printf 'tooling: eval odin diagnostic mapping\n'
if ./odinl eval examples/higher-order.odinl '(+ 1 "bad")' --check >"$tmp_dir/bad-eval-check.out" 2>"$tmp_dir/bad-eval-check.err"; then
    printf 'failed: bad eval check unexpectedly succeeded\n' >&2
    exit 1
fi
if ! grep -q 'examples/higher-order.odinl:<eval>:1:1 Error: Cannot convert' "$tmp_dir/bad-eval-check.err"; then
    printf 'failed: bad eval check diagnostic did not point at <eval>\n' >&2
    cat "$tmp_dir/bad-eval-check.err" >&2
    exit 1
fi

printf 'tooling: legacy eval compile path\n'
./odinl examples/higher-order.odinl --eval '(reduce add 0 (new []int [1 2 3]))' -o "$tmp_dir/legacy-eval.odin"
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

    printf 'tooling: emacs keybindings and eval comment\n'
    emacs -Q --batch --eval \
        "(progn
           (defvar clojure-mode-map (make-sparse-keymap))
           (defvar cider-mode nil)
           (defvar clj-refactor-mode nil)
           (define-derived-mode clojure-mode prog-mode \"Clojure\")
           (defun clojure--put-indentation-spec (&rest _args) nil)
           (provide (quote clojure-mode))
           (add-to-list (quote load-path) \"emacs\")
           (require (quote odinl-eval))
           (let ((file (make-temp-file (expand-file-name \".odinl-emacs-test-\" default-directory) nil \".odinl\")))
             (unwind-protect
                 (progn
                   (with-temp-file file
                     (insert \"(package main)\\n(import \\\"core:fmt\\\")\\n\\n(proc add [a: int, b: int] -> int\\n  (+ a b))\\n\\n(proc main []\\n  (fmt.println \\\"from main\\\"))\\n\\n(comment\\n  (add 1 2)\\n  (main))\\n\"))
                   (find-file file)
                   (odinl-mode)
                   (dolist (binding (list (cons \"C-c C-e\" (quote odinl-eval-form-at-point))
                                          (cons \"C-c C-c\" (quote odinl-eval-top-level-form))
                                          (cons \"C-c C-i\" (quote odinl-insert-form-result))
                                          (cons \"C-c C-k\" (quote odinl-eval-buffer))
                                          (cons \"C-c C-v\" (quote odinl-check-buffer))
                                          (cons \"C-c C-b\" (quote odinl-build-buffer))
                                          (cons \"C-c C-m\" (quote odinl-expand-form-at-point))))
                     (unless (eq (key-binding (kbd (car binding))) (cdr binding))
                       (error \"Missing binding %s\" (car binding))))
                   (goto-char (point-min))
                   (search-forward \"(add 1 2)\")
                   (call-interactively (quote odinl-expand-form-at-point))
                   (with-current-buffer odinl-generated-buffer-name
                     (goto-char (point-min))
                     (unless (search-forward \"fmt.println(add(1, 2))\" nil t)
                       (error \"Expected generated eval wrapper\")))
                   (goto-char (point-min))
                   (search-forward \"(add 1 2)\")
                   (call-interactively (quote odinl-insert-form-result))
                   (goto-char (point-min))
                   (unless (search-forward \";; => 3\" nil t)
                     (error \"Expected inserted eval comment\"))
                   (goto-char (point-min))
                   (search-forward \"(main)\")
                   (call-interactively (quote odinl-insert-form-result))
                   (goto-char (point-min))
                   (unless (search-forward \";; => from main\" nil t)
                     (error \"Expected inserted void-call eval comment\")))
               (ignore-errors (kill-buffer (current-buffer)))
               (delete-file file))))"
else
    printf 'tooling: emacs not found, skipping byte compile\n'
fi

printf 'tooling integration ok\n'
