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

printf 'tooling: symbols command\n'
./odinl symbols examples/sequences.odinl > "$tmp_dir/symbols.tsv"
if ! grep -q "$(printf 'proc\tactive-count')" "$tmp_dir/symbols.tsv"; then
    printf 'failed: symbols output did not include active-count proc\n' >&2
    cat "$tmp_dir/symbols.tsv" >&2
    exit 1
fi
if ! grep -q "$(printf 'field\tUser.name')" "$tmp_dir/symbols.tsv"; then
    printf 'failed: symbols output did not include User.name field\n' >&2
    cat "$tmp_dir/symbols.tsv" >&2
    exit 1
fi

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
if ! grep -q "$tmp_dir/bad.odinl:5:16 Error: Cannot convert" "$tmp_dir/bad-check.err"; then
    printf 'failed: bad check diagnostic did not map back to .odinl\n' >&2
    cat "$tmp_dir/bad-check.err" >&2
    exit 1
fi
cat > "$tmp_dir/bad-statements.odinl" <<'EOF'
(package main)

(proc main []
  (return))

(proc if-test [] -> int
  (if "bad"
    1
    0))

(proc when-test []
  (when "bad"
    (return)))

(proc set-test []
  (let [x 1]
    (set! x "bad")))

(proc each-test []
  (each [x 123]
    (return)))

(proc return-test [] -> int
  (return "bad"))
EOF
if ./odinl check "$tmp_dir/bad-statements.odinl" >"$tmp_dir/bad-statements.out" 2>"$tmp_dir/bad-statements.err"; then
    printf 'failed: bad statement check unexpectedly succeeded\n' >&2
    exit 1
fi
for expected in \
    "$tmp_dir/bad-statements.odinl:7:7 Error: Non-boolean condition" \
    "$tmp_dir/bad-statements.odinl:12:9 Error: Non-boolean condition" \
    "$tmp_dir/bad-statements.odinl:17:13 Error: Cannot convert" \
    "$tmp_dir/bad-statements.odinl:20:12 Error: Cannot iterate" \
    "$tmp_dir/bad-statements.odinl:24:11 Error: Cannot convert"
do
    if ! grep -q "$expected" "$tmp_dir/bad-statements.err"; then
        printf 'failed: bad statement diagnostic did not map to expected source location: %s\n' "$expected" >&2
        cat "$tmp_dir/bad-statements.err" >&2
        exit 1
    fi
done

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

printf 'tooling: eval tap output\n'
tap_output=$(./odinl eval examples/tap.odinl '(tap> :answer 42)')
tap_expected=$(printf 'answer: 42\n42')
assert_eq "$tap_expected" "$tap_output" "tap eval output"

printf 'tooling: eval save cache\n'
cache_dir="$tmp_dir/cache"
saved_output=$(ODINL_CACHE_DIR="$cache_dir" ./odinl eval examples/higher-order.odinl '(reduce add 0 (new []int [1 2 3]))' --save sum)
assert_eq "6" "$saved_output" "saved eval output"
saved_path=$(ODINL_CACHE_DIR="$cache_dir" ./odinl cache path sum)
assert_eq "$cache_dir/sum" "$saved_path" "cache path"
assert_eq "6" "$(cat "$saved_path")" "saved cache content"
assert_eq "sum" "$(ODINL_CACHE_DIR="$cache_dir" ./odinl cache list)" "cache list"
ODINL_CACHE_DIR="$cache_dir" ./odinl cache rm sum
assert_eq "" "$(ODINL_CACHE_DIR="$cache_dir" ./odinl cache list)" "cache list after rm"

printf 'tooling: eval file-backed dev helpers\n'
cat > "$tmp_dir/dev-io.odinl" <<'EOF'
(package main)
(import json "core:encoding/json")
(import os "core:os")

(struct Note {
  :title string
  :body string
})

(struct Count {
  :n int
})

(proc write-read-count [path: string] -> int
  (let [write-err (spit path "odinl")]
    (if (!= write-err nil)
      0
      (let [[data read-err] (slurp path)]
        (if (!= read-err nil)
          0
          (do
            (defer (delete data))
            (len data)))))))

(proc save-note-json [path: string] -> bool
  (let [note (Note {:title "hello" :body "odinl"})
        [data marshal-err] (json.marshal note)]
    (if (!= marshal-err nil)
      false
      (do
        (defer (delete data))
        (== (spit path data) nil)))))

(proc save-count-json [path: string, n: int] -> bool
  (let [[data marshal-err] (json.marshal (Count {:n n}))]
    (if (!= marshal-err nil)
      false
      (do
        (defer (delete data))
        (== (spit path data) nil)))))

(proc load-count-json [path: string] -> int
  (let [[data read-err] (slurp path)]
    (if (!= read-err nil)
      0
      (do
        (defer (delete data))
        (let [count (Count {})
              unmarshal-err (json.unmarshal data (& count))]
          (if (!= unmarshal-err nil)
            0
            (:n count)))))))
EOF
file_eval_output=$(./odinl eval "$tmp_dir/dev-io.odinl" "(write-read-count \"$tmp_dir/odinl-cache.txt\")")
assert_eq "5" "$file_eval_output" "file-backed eval output"
json_eval_output=$(./odinl eval "$tmp_dir/dev-io.odinl" "(save-note-json \"$tmp_dir/odinl-note.json\")")
assert_eq "true" "$json_eval_output" "json save eval output"
if ! grep -q '"title":"hello"' "$tmp_dir/odinl-note.json"; then
    printf 'failed: explicit json.marshal did not write expected JSON\n' >&2
    cat "$tmp_dir/odinl-note.json" >&2
    exit 1
fi
count_save_output=$(./odinl eval "$tmp_dir/dev-io.odinl" "(save-count-json \"$tmp_dir/odinl-count.json\" 42)")
assert_eq "true" "$count_save_output" "json count save eval output"
count_load_output=$(./odinl eval "$tmp_dir/dev-io.odinl" "(load-count-json \"$tmp_dir/odinl-count.json\")")
assert_eq "42" "$count_load_output" "json load eval output"

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

printf 'tooling: macroexpand command\n'
./odinl macroexpand examples/data-literals.odinl '(with-allocator [allocator context.temp_allocator] (let [buffer (make [dynamic]int)] (defer (delete buffer))))' -o "$tmp_dir/macroexpand.odinl" --map "$tmp_dir/macroexpand.map"
assert_file_nonempty "$tmp_dir/macroexpand.odinl" "macroexpand output"
assert_file_nonempty "$tmp_dir/macroexpand.map" "macroexpand source map"
if ! grep -q '(set! context.allocator allocator)' "$tmp_dir/macroexpand.odinl"; then
    printf 'failed: macroexpand output did not include allocator set\n' >&2
    cat "$tmp_dir/macroexpand.odinl" >&2
    exit 1
fi
if ! grep -q 'odinl-old-allocator-1 context.allocator' "$tmp_dir/macroexpand.odinl"; then
    printf 'failed: macroexpand output did not include old allocator binding\n' >&2
    cat "$tmp_dir/macroexpand.odinl" >&2
    exit 1
fi
if ! grep -q '^2 2 ' "$tmp_dir/macroexpand.map"; then
    printf 'failed: macroexpand source map did not include allocator expression line\n' >&2
    cat "$tmp_dir/macroexpand.map" >&2
    exit 1
fi
./odinl macroexpand examples/data-literals.odinl '(with-temp-allocator [allocator] (let [buffer (make [dynamic]int)] (defer (delete buffer))))' -o "$tmp_dir/macroexpand-temp.odinl"
assert_file_nonempty "$tmp_dir/macroexpand-temp.odinl" "macroexpand temp output"
if ! grep -q 'runtime.default-temp-allocator-temp-begin' "$tmp_dir/macroexpand-temp.odinl"; then
    printf 'failed: macroexpand temp output did not include temp begin\n' >&2
    cat "$tmp_dir/macroexpand-temp.odinl" >&2
    exit 1
fi
if ! grep -q 'runtime.default-temp-allocator-temp-end' "$tmp_dir/macroexpand-temp.odinl"; then
    printf 'failed: macroexpand temp output did not include temp end\n' >&2
    cat "$tmp_dir/macroexpand-temp.odinl" >&2
    exit 1
fi

printf 'tooling: eval main command\n'
main_eval_output=$(./odinl eval examples/hello.odinl '(main)')
assert_eq "hello from odinl" "$main_eval_output" "eval main output"

printf 'tooling: sequence example evals\n'
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(split-front-length)')" "split-front-length"
assert_eq "4" "$(./odinl eval examples/sequence-helpers.odinl '(first-kept-square)')" "first-kept-square"
assert_eq "12" "$(./odinl eval examples/sequence-helpers.odinl '(with-delete-total)')" "with-delete-total"
assert_eq "45" "$(./odinl eval examples/sequence-helpers.odinl '(age-for-grace)')" "age-for-grace"
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(chunk-count)')" "chunk-count"
assert_eq "2" "$(./odinl eval examples/sequence-helpers.odinl '(repeated-two-count)')" "repeated-two-count"
assert_eq "3" "$(./odinl eval examples/sequence-helpers.odinl '(indexed-name-count)')" "indexed-name-count"
assert_eq "6" "$(./odinl eval examples/sequence-helpers.odinl '(key-value-count)')" "key-value-count"
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
assert_eq "3" "$(./odinl eval examples/data-literals.odinl '(temp-scoped-buffer-len)')" "temp-scoped-buffer-len"
assert_eq "1500" "$(./odinl eval examples/core-time-slice.odinl '(duration-ms)')" "duration-ms"
assert_eq "2" "$(./odinl eval examples/core-time-slice.odinl '(fixed-date-weekday)')" "fixed-date-weekday"
assert_eq "10" "$(./odinl eval examples/core-time-slice.odinl '(fixed-date-string-length)')" "fixed-date-string-length"
assert_eq "17" "$(./odinl eval examples/core-time-slice.odinl '(min-max-score)')" "min-max-score"
assert_eq "2" "$(./odinl eval examples/core-time-slice.odinl '(search-score)')" "search-score"
parallel_eval_output=$(
    printf '%s\n' \
        '(duration-ms)' \
        '(fixed-date-weekday)' \
        '(fixed-date-string-length)' \
        '(min-max-score)' \
        '(search-score)' |
        xargs -P 5 -I FORM ./odinl eval examples/core-time-slice.odinl FORM |
        sort
)
parallel_eval_expected=$(printf '10\n1500\n17\n2\n2')
assert_eq "$parallel_eval_expected" "$parallel_eval_output" "parallel eval output"
assert_eq "parsed 1" "$(./odinl eval examples/error-handling.odinl "(parse-label \"one\")")" "parse-label"
assert_eq "not parsed" "$(./odinl eval examples/error-handling.odinl "(parse-label \"missing\")")" "parse-label-missing"
assert_eq "3" "$(./odinl eval examples/error-handling.odinl "(parsed-total \"one\" \"two\")")" "parsed-total"
assert_eq "0" "$(./odinl eval examples/error-handling.odinl "(read-byte-count \"tmp/does-not-exist.txt\")")" "read-byte-count-missing"
tap_age_output=$(./odinl eval examples/tap.odinl '(inspected-age)')
tap_age_expected=$(printf 'user: User{name = "Ada", age = 36}\nage: 36\n36')
assert_eq "$tap_age_expected" "$tap_age_output" "inspected-age"
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
if ./odinl eval examples/higher-order.odinl '(let [x: int "bad"] x)' --check >"$tmp_dir/bad-eval-let-check.out" 2>"$tmp_dir/bad-eval-let-check.err"; then
    printf 'failed: bad eval let check unexpectedly succeeded\n' >&2
    exit 1
fi
if ! grep -q 'examples/higher-order.odinl:<eval>:1:14 Error: Cannot convert' "$tmp_dir/bad-eval-let-check.err"; then
    printf 'failed: bad eval let check diagnostic did not point at binding value\n' >&2
    cat "$tmp_dir/bad-eval-let-check.err" >&2
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
    ODINL_CACHE_DIR="$tmp_dir/emacs-cache" emacs -Q --batch --eval \
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
                     (insert \"(package main)\\n(import \\\"core:fmt\\\")\\n\\n// Adds two ints.\\n(proc add [a: int, b: int] -> int\\n  (+ a b))\\n\\n(proc add-two [a: int, b: int] -> int\\n  (add a b))\\n\\n(proc main []\\n  (fmt.println \\\"from main\\\"))\\n\\n(comment\\n  (add 1 2)\\n  (add-two 1 2)\\n  (with-allocator [allocator context.temp_allocator]\\n    (add 2 1))\\n  (if-ok [value err (read)] value 0)\\n  (main))\\n\"))
                   (find-file file)
                   (odinl-mode)
                   (setq odinl-test-source-buffer (current-buffer))
                   (let ((diagnostic-buffer (odinl--prepare-diagnostic-buffer odinl-result-buffer-name)))
                     (with-current-buffer diagnostic-buffer
                       (let ((inhibit-read-only t)
                             (buffer-read-only nil))
                         (insert file \":6:4 Error: simulated diagnostic\\n\")
                         (insert file \":<eval>:1:14 Error: simulated eval diagnostic\\n\")
                         (odinl--finish-output-buffer t))
                       (unless (eq major-mode (quote compilation-mode))
                         (error \"Expected OdinL diagnostic buffer to use compilation-mode\"))
                       (goto-char (point-min))
                       (let ((msg (compilation-next-error 1)))
                         (unless msg
                           (error \"Expected compilation-next-error to find OdinL diagnostic\")))))
                   (unless (eq (key-binding (kbd \"M-.\")) (quote xref-find-definitions))
                     (error \"Missing M-. xref binding\"))
                   (let ((symbols (odinl--symbols)))
                     (unless (seq-find (lambda (sym) (equal (plist-get sym :name) \"add\")) symbols)
                       (error \"Expected add in odinl symbols: %S\" symbols)))
                   (let ((docs (odinl--symbol-doc-candidates \"add\")))
                     (unless (and docs (equal (plist-get (car docs) :doc) \"Adds two ints.\"))
                       (error \"Expected add docs, got: %S\" docs)))
                   (let ((docs (odinl--symbol-doc-candidates \"fmt.println\")))
                     (unless docs
                       (error \"Expected fmt.println docs\")))
                   (let ((docs (odinl--symbol-doc-candidates \"if-ok\")))
                     (unless (and docs (string-match-p \"Odin error result\" (plist-get (car docs) :doc)))
                       (error \"Expected if-ok built-in docs, got: %S\" docs)))
                   (with-temp-buffer
                     (insert \"/*\\n * Block docs.\\n * More docs.\\n */\\nthing :: proc() {}\\n\")
                     (goto-char (point-min))
                     (search-forward \"thing ::\")
                     (let ((doc (odinl--preceding-odin-doc (line-beginning-position))))
                       (unless (equal doc \"Block docs.\\nMore docs.\")
                         (error \"Expected block docs, got: %S\" doc))))
                   (with-temp-buffer
                     (odinl-mode)
                     (insert \";; semi\\nafter-semi\\n// slash\\nafter-slash\\n(code) /* block\\nmore */ tail\\n\")
                     (font-lock-ensure)
                     (goto-char (point-min))
                     (search-forward \"semi\")
                     (unless (nth 4 (syntax-ppss))
                       (error \"Expected ;; to be comment syntax\"))
                     (search-forward \"after-semi\")
                     (when (nth 4 (syntax-ppss))
                       (error \"Expected ;; comment to end at newline\"))
                     (search-forward \"slash\")
                     (unless (nth 4 (syntax-ppss))
                       (error \"Expected // to be comment syntax\"))
                     (unless (eq (get-text-property (point) (quote face)) (quote font-lock-comment-face))
                       (error \"Expected // to use comment face\"))
                     (search-forward \"after-slash\")
                     (when (nth 4 (syntax-ppss))
                       (error \"Expected // comment to end at newline\"))
                     (search-forward \"block\")
                     (unless (nth 4 (syntax-ppss))
                       (error \"Expected /* */ to be comment syntax\"))
                     (unless (eq (get-text-property (point) (quote face)) (quote font-lock-comment-face))
                       (error \"Expected /* */ to use comment face\"))
                     (search-forward \"tail\")
                     (when (nth 4 (syntax-ppss))
                       (error \"Expected block comment to end\")))
                   (goto-char (point-min))
                   (search-forward \"add [\")
                   (backward-word)
                   (call-interactively (quote odinl-doc-at-point))
                   (let ((doc-text (with-current-buffer odinl-doc-buffer-name
                                     (buffer-substring-no-properties (point-min) (point-max)))))
                     (unless (string-match-p \"Adds two ints\" doc-text)
                       (error \"Expected displayed add docs, got: %s\" doc-text)))
                   (goto-char (point-min))
                   (search-forward \"if-ok\")
                   (call-interactively (quote odinl-doc-at-point))
                   (let ((doc-text (with-current-buffer odinl-doc-buffer-name
                                     (buffer-substring-no-properties (point-min) (point-max)))))
                     (unless (string-match-p \"Odin error result\" doc-text)
                       (error \"Expected displayed if-ok docs, got: %s\" doc-text)))
                   (let ((defs (xref-backend-definitions (quote odinl) \"add\")))
                     (unless defs
                       (error \"Expected xref definition for add\")))
                   (goto-char (point-min))
                   (search-forward \"(add-two 1 2)\")
                   (backward-char 7)
                   (unless (equal (odinl--identifier-at-point) \"add-two\")
                     (error \"Expected add-two identifier, got: %S\" (odinl--identifier-at-point)))
                   (let ((defs (xref-backend-definitions (quote odinl) (odinl--identifier-at-point))))
                     (unless defs
                       (error \"Expected xref definition for same-file hyphenated proc\")))
                   (let ((defs (xref-backend-definitions (quote odinl) \"map\")))
                     (unless (and defs (string-match-p \"src/odinl/emit\\\\.odin\" (format \"%S\" defs)))
                       (error \"Expected implementation xref for OdinL helper map, got: %S\" defs)))
                   (let ((defs (xref-backend-definitions (quote odinl) \"proc\")))
                     (unless (and defs (string-match-p \"src/odinl/parse\\\\.odin\" (format \"%S\" defs)))
                       (error \"Expected implementation xref for OdinL form proc, got: %S\" defs)))
                   (let ((defs (xref-backend-definitions (quote odinl) \"fmt.println\")))
                     (unless defs
                       (error \"Expected xref definition for fmt.println\")))
                   (let ((candidates (odinl--completion-candidates)))
                     (unless (and (member \"add\" candidates)
                                  (member \"proc\" candidates)
                                  (member \"map\" candidates)
                                  (member \"fmt.println\" candidates))
                       (error \"Expected completion candidates, got: %S\" candidates)))
                   (dolist (binding (list (cons \"C-c C-e\" (quote odinl-eval-form-at-point))
                                          (cons \"C-c C-c\" (quote odinl-eval-top-level-form))
                                          (cons \"C-c C-i\" (quote odinl-insert-form-result))
                                          (cons \"C-c C-.\" (quote odinl-doc-at-point))
                                          (cons \"C-c C-k\" (quote odinl-eval-buffer))
                                          (cons \"C-c C-v\" (quote odinl-check-buffer))
                                          (cons \"C-c C-b\" (quote odinl-build-buffer))
                                          (cons \"C-c C-m\" (quote odinl-expand-form-at-point))
                                          (cons \"C-c M-m\" (quote odinl-macroexpand-form-at-point))
                                          (cons \"C-c C-w\" (quote odinl-save-form-result))
                                          (cons \"C-c C-l\" (quote odinl-cache-list))
                                          (cons \"C-c C-o\" (quote odinl-cache-open))
                                          (cons \"C-c C-d\" (quote odinl-cache-rm))))
                     (unless (eq (key-binding (kbd (car binding))) (cdr binding))
                       (error \"Missing binding %s\" (car binding))))
                   (goto-char (point-min))
                   (search-forward \"  (with-allocator\")
                   (beginning-of-line)
                   (skip-chars-forward \" \\t\")
                   (let* ((bounds (odinl--form-bounds-at-point))
                          (form (buffer-substring-no-properties (car bounds) (cdr bounds))))
                     (unless (string-prefix-p \"(with-allocator\" form)
                       (error \"Expected with-allocator form, got: %s\" form)))
                   (call-interactively (quote odinl-macroexpand-form-at-point))
                   (let ((macro-text (with-current-buffer odinl-macroexpand-buffer-name
                                       (buffer-substring-no-properties (point-min) (point-max)))))
                     (unless (string-match-p \"context\\\\.allocator allocator\" macro-text)
                       (error \"Expected macroexpand allocator set, got: %s\" macro-text)))
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
                   (search-forward \"(add 1 2)\")
                   (odinl-save-form-result \"emacs-sum\")
                   (let ((cache-path (expand-file-name \"emacs-sum\" \"$tmp_dir/emacs-cache\")))
                     (unless (file-exists-p cache-path)
                       (error \"Expected saved eval cache file\"))
                     (with-temp-buffer
                       (insert-file-contents cache-path)
                       (unless (equal (buffer-string) \"3\\n\")
                         (error \"Expected saved eval cache content\"))))
                   (odinl-cache-list)
                   (let ((cache-list (with-current-buffer odinl-result-buffer-name
                                       (buffer-substring-no-properties (point-min) (point-max)))))
                     (unless (string-match-p \"emacs-sum\" cache-list)
                       (error \"Expected saved eval cache listing\")))
                   (odinl-cache-rm \"emacs-sum\")
                   (when (file-exists-p (expand-file-name \"emacs-sum\" \"$tmp_dir/emacs-cache\"))
                     (error \"Expected removed eval cache file\"))
                   (let ((source-buffer odinl-test-source-buffer))
                     (set-buffer source-buffer)
                     (goto-char (point-min))
                     (search-forward \"(+ a b)\")
                     (delete-region (line-beginning-position) (line-end-position))
                     (insert \"  (+ a \\\"bad\\\"))\")
                     (save-buffer)
                     (call-interactively (quote odinl-check-buffer))
                     (with-current-buffer odinl-result-buffer-name
                       (unless (eq major-mode (quote compilation-mode))
                         (error \"Expected failed check buffer to use compilation-mode\"))
                       (goto-char (point-min))
                       (unless (search-forward \".odinl:\" nil t)
                         (error \"Expected failed check to contain OdinL diagnostic\"))
                       (goto-char (point-min))
                       (unless (search-forward \"Cannot convert\" nil t)
                         (error \"Expected failed check to report the intended type error\"))
                       (goto-char (point-min))
                       (unless (compilation-next-error 1)
                         (error \"Expected failed check diagnostic to be navigable\")))
                     (set-buffer source-buffer)
                     (goto-char (point-min))
                     (next-error)
                     (unless (equal (current-buffer) source-buffer)
                       (error \"Expected next-error from source to stay in OdinL source buffer\"))
                     (unless (= (line-number-at-pos) 6)
                       (error \"Expected next-error from source to jump to diagnostic line, got %s\"
                              (line-number-at-pos)))
                     (unless (eq next-error-last-buffer (get-buffer odinl-result-buffer-name))
                       (error \"Expected OdinL result buffer to be the active next-error buffer\"))
                     (set-buffer source-buffer)
                     (goto-char (point-min))
                     (search-forward \"(+ a \\\"bad\\\")\")
                     (delete-region (line-beginning-position) (line-end-position))
                     (insert \"  (+ a b))\")
                     (save-buffer))
                   (set-buffer odinl-test-source-buffer)
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
