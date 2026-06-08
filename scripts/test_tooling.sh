#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

odin build cmd/kvist

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
./kvist compile examples/language/hello.kvist -o "$tmp_dir/hello.odin" --map "$tmp_dir/hello.map"
assert_file_nonempty "$tmp_dir/hello.odin" "compile output"
assert_file_nonempty "$tmp_dir/hello.map" "compile source map"
odin check "$tmp_dir/hello.odin" -file

printf 'tooling: symbols command\n'
./kvist symbols examples/collections/sequences.kvist > "$tmp_dir/symbols.tsv"
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
./kvist check examples/language/hello.kvist --generated "$tmp_dir/check.odin"
assert_file_nonempty "$tmp_dir/check.odin" "check generated output"

printf 'tooling: check diagnostic mapping\n'
cat > "$tmp_dir/bad.kvist" <<'EOF'
(package main)
(import "core:fmt")

(proc main []
  (let [x: int "bad"]
    (fmt.println x)))
EOF
if ./kvist check "$tmp_dir/bad.kvist" >"$tmp_dir/bad-check.out" 2>"$tmp_dir/bad-check.err"; then
    printf 'failed: bad check unexpectedly succeeded\n' >&2
    exit 1
fi
if ! grep -q "$tmp_dir/bad.kvist:5:16 Error: Cannot convert" "$tmp_dir/bad-check.err"; then
    printf 'failed: bad check diagnostic did not map back to .kvist\n' >&2
    cat "$tmp_dir/bad-check.err" >&2
    exit 1
fi
cat > "$tmp_dir/bad-statements.kvist" <<'EOF'
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
if ./kvist check "$tmp_dir/bad-statements.kvist" >"$tmp_dir/bad-statements.out" 2>"$tmp_dir/bad-statements.err"; then
    printf 'failed: bad statement check unexpectedly succeeded\n' >&2
    exit 1
fi
for expected in \
    "$tmp_dir/bad-statements.kvist:7:7 Error: Non-boolean condition" \
    "$tmp_dir/bad-statements.kvist:12:9 Error: Non-boolean condition" \
    "$tmp_dir/bad-statements.kvist:17:13 Error: Cannot convert" \
    "$tmp_dir/bad-statements.kvist:20:12 Error: Cannot iterate" \
    "$tmp_dir/bad-statements.kvist:24:11 Error: Cannot convert"
do
    if ! grep -q "$expected" "$tmp_dir/bad-statements.err"; then
        printf 'failed: bad statement diagnostic did not map to expected source location: %s\n' "$expected" >&2
        cat "$tmp_dir/bad-statements.err" >&2
        exit 1
    fi
done

printf 'tooling: build command\n'
./kvist build examples/language/hello.kvist --generated "$tmp_dir/build.odin"
assert_file_nonempty "$tmp_dir/build.odin" "build generated output"

printf 'tooling: run command\n'
run_output=$(./kvist run examples/language/hello.kvist)
assert_eq "hello from kvist" "$run_output" "run output"

printf 'tooling: eval command\n'
eval_output=$(./kvist eval examples/collections/higher-order.kvist '(threaded-total)' --generated "$tmp_dir/eval.odin")
assert_eq "6" "$eval_output" "eval output"
assert_file_nonempty "$tmp_dir/eval.odin" "eval generated output"

printf 'tooling: eval tap output\n'
tap_output=$(./kvist eval examples/collections/tap.kvist '(tap> :answer 42)')
tap_expected=$(printf 'answer: 42\n42')
assert_eq "$tap_expected" "$tap_output" "tap eval output"

printf 'tooling: eval save cache\n'
cache_dir="$tmp_dir/cache"
saved_output=$(KVIST_CACHE_DIR="$cache_dir" ./kvist eval examples/collections/higher-order.kvist '(threaded-total)' --save sum)
assert_eq "6" "$saved_output" "saved eval output"
saved_path=$(KVIST_CACHE_DIR="$cache_dir" ./kvist cache path sum)
assert_eq "$cache_dir/sum" "$saved_path" "cache path"
assert_eq "6" "$(cat "$saved_path")" "saved cache content"
assert_eq "sum" "$(KVIST_CACHE_DIR="$cache_dir" ./kvist cache list)" "cache list"
KVIST_CACHE_DIR="$cache_dir" ./kvist cache rm sum
assert_eq "" "$(KVIST_CACHE_DIR="$cache_dir" ./kvist cache list)" "cache list after rm"

printf 'tooling: eval file-backed dev helpers\n'
cat > "$tmp_dir/dev-io.kvist" <<'EOF'
(package main)
(import io "kvist:io")
(import json "kvist:json")

(defstruct Note {
  :title string
  :body string
})

(defstruct Count {
  :n int
})

(proc write-read-count [path: string] -> int
  (let [write-err (io/write path "kvist")]
    (if (!= write-err nil)
      0
      (let [[data read-err] (io/read path)]
        (if (!= read-err nil)
          0
          (do
            (defer (delete data))
            (len data)))))))

(proc save-note-json [path: string] -> bool
  (let [[marshal-err write-err] (json/write path (Note {:title "hello" :body "kvist"}))]
    (and (== marshal-err nil)
         (== write-err nil))))

(proc save-count-json [path: string, n: int] -> bool
  (let [[marshal-err write-err] (json/write path (Count {:n n}))]
    (and (== marshal-err nil)
         (== write-err nil))))

(proc load-count-json [path: string] -> int
  (let [[count read-err unmarshal-err] (json/read-as Count path)]
    (if (or (!= read-err nil)
            (!= unmarshal-err nil))
      0
      (:n count))))
EOF
file_eval_output=$(./kvist eval "$tmp_dir/dev-io.kvist" "(write-read-count \"$tmp_dir/kvist-cache.txt\")")
assert_eq "5" "$file_eval_output" "file-backed eval output"
json_eval_output=$(./kvist eval "$tmp_dir/dev-io.kvist" "(save-note-json \"$tmp_dir/kvist-note.json\")")
assert_eq "true" "$json_eval_output" "json save eval output"
if ! grep -q '"title":"hello"' "$tmp_dir/kvist-note.json"; then
    printf 'failed: explicit json.marshal did not write expected JSON\n' >&2
    cat "$tmp_dir/kvist-note.json" >&2
    exit 1
fi
count_save_output=$(./kvist eval "$tmp_dir/dev-io.kvist" "(save-count-json \"$tmp_dir/kvist-count.json\" 42)")
assert_eq "true" "$count_save_output" "json count save eval output"
count_load_output=$(./kvist eval "$tmp_dir/dev-io.kvist" "(load-count-json \"$tmp_dir/kvist-count.json\")")
assert_eq "42" "$count_load_output" "json load eval output"

printf 'tooling: expand command\n'
./kvist expand examples/language/data-literals.kvist '(temp-buffer-len)' -o "$tmp_dir/expand.odin"
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
./kvist macroexpand examples/language/data-literals.kvist '(with-allocator [allocator context.temp_allocator] (let [buffer (make [dynamic]int)] (defer (delete buffer))))' -o "$tmp_dir/macroexpand.kvist" --map "$tmp_dir/macroexpand.map"
assert_file_nonempty "$tmp_dir/macroexpand.kvist" "macroexpand output"
assert_file_nonempty "$tmp_dir/macroexpand.map" "macroexpand source map"
if ! grep -q '(set! context.allocator allocator)' "$tmp_dir/macroexpand.kvist"; then
    printf 'failed: macroexpand output did not include allocator set\n' >&2
    cat "$tmp_dir/macroexpand.kvist" >&2
    exit 1
fi
if ! grep -q 'kvist-old-allocator-1 context.allocator' "$tmp_dir/macroexpand.kvist"; then
    printf 'failed: macroexpand output did not include old allocator binding\n' >&2
    cat "$tmp_dir/macroexpand.kvist" >&2
    exit 1
fi
if ! grep -q '^2 2 ' "$tmp_dir/macroexpand.map"; then
    printf 'failed: macroexpand source map did not include allocator expression line\n' >&2
    cat "$tmp_dir/macroexpand.map" >&2
    exit 1
fi
./kvist macroexpand examples/language/data-literals.kvist '(with-temp-allocator [allocator] (let [buffer (make [dynamic]int)] (defer (delete buffer))))' -o "$tmp_dir/macroexpand-temp.kvist"
assert_file_nonempty "$tmp_dir/macroexpand-temp.kvist" "macroexpand temp output"
if ! grep -q 'runtime.default-temp-allocator-temp-begin' "$tmp_dir/macroexpand-temp.kvist"; then
    printf 'failed: macroexpand temp output did not include temp begin\n' >&2
    cat "$tmp_dir/macroexpand-temp.kvist" >&2
    exit 1
fi
if ! grep -q 'runtime.default-temp-allocator-temp-end' "$tmp_dir/macroexpand-temp.kvist"; then
    printf 'failed: macroexpand temp output did not include temp end\n' >&2
    cat "$tmp_dir/macroexpand-temp.kvist" >&2
    exit 1
fi

printf 'tooling: eval main command\n'
main_eval_output=$(./kvist eval examples/language/hello.kvist '(main)')
assert_eq "hello from kvist" "$main_eval_output" "eval main output"

printf 'tooling: sequence example evals\n'
assert_eq "2" "$(./kvist eval examples/collections/sequence-helpers.kvist '(split-front-length)')" "split-front-length"
assert_eq "4" "$(./kvist eval examples/collections/sequence-helpers.kvist '(first-kept-square)')" "first-kept-square"
assert_eq "12" "$(./kvist eval examples/collections/sequence-helpers.kvist '(deferred-total)')" "deferred-total"
assert_eq "45" "$(./kvist eval examples/collections/sequence-helpers.kvist '(age-for-grace)')" "age-for-grace"
assert_eq "2" "$(./kvist eval examples/collections/sequence-helpers.kvist '(chunk-count)')" "chunk-count"
assert_eq "2" "$(./kvist eval examples/collections/sequence-helpers.kvist '(repeated-two-count)')" "repeated-two-count"
assert_eq "3" "$(./kvist eval examples/collections/sequence-helpers.kvist '(indexed-name-count)')" "indexed-name-count"
assert_eq "6" "$(./kvist eval examples/collections/sequence-helpers.kvist '(key-value-count)')" "key-value-count"
assert_eq "3" "$(./kvist eval examples/collections/sequence-helpers.kvist '(even-group-count)')" "even-group-count"
assert_eq "10" "$(./kvist eval examples/collections/sequence-helpers.kvist '(range-total)')" "range-total"
assert_eq "3" "$(./kvist eval examples/collections/sequence-helpers.kvist '(repeated-answer-count)')" "repeated-answer-count"
assert_eq "odin" "$(./kvist eval examples/collections/sequence-helpers.kvist '(repeated-word-last)')" "repeated-word-last"
assert_eq "8" "$(./kvist eval examples/collections/sequence-helpers.kvist '(iterated-last)')" "iterated-last"
assert_eq "9" "$(./kvist eval examples/collections/sequence-helpers.kvist '(cycled-total)')" "cycled-total"
assert_eq "5" "$(./kvist eval examples/collections/sequence-helpers.kvist '(counted-cycle)')" "counted-cycle"
assert_eq "13" "$(./kvist eval examples/collections/sequence-helpers.kvist '(trimmed-sum)')" "trimmed-sum"
assert_eq "40" "$(./kvist eval examples/collections/sequence-helpers.kvist '(rest-second-empty-score)')" "rest-second-empty-score"
assert_eq "4" "$(./kvist eval examples/collections/sequence-helpers.kvist '(concat-reversed-first)')" "concat-reversed-first"
assert_eq "26" "$(./kvist eval examples/collections/sequence-helpers.kvist '(interposed-total)')" "interposed-total"
assert_eq "33" "$(./kvist eval examples/collections/sequence-helpers.kvist '(interleaved-total)')" "interleaved-total"
assert_eq "2" "$(./kvist eval examples/collections/sequence-helpers.kvist '(shuffled-first)')" "shuffled-first"
assert_eq "2" "$(./kvist eval examples/collections/sequence-helpers.kvist '(shuffled-in-place-first)')" "shuffled-in-place-first"
assert_eq "2" "$(./kvist eval examples/collections/sequence-helpers.kvist '(sorted-second)')" "sorted-second"
assert_eq "4" "$(./kvist eval examples/collections/sequence-helpers.kvist '(descending-first)')" "descending-first"
assert_eq "1" "$(./kvist eval examples/collections/sequence-helpers.kvist '(sorted-in-place-first)')" "sorted-in-place-first"
assert_eq "4" "$(./kvist eval examples/collections/sequence-helpers.kvist '(reversed-in-place-first)')" "reversed-in-place-first"
assert_eq "4" "$(./kvist eval examples/collections/sequence-helpers.kvist '(descending-in-place-first)')" "descending-in-place-first"
assert_eq "12" "$(./kvist eval examples/collections/sequence-helpers.kvist '(doubled-in-place-total)')" "doubled-in-place-total"
assert_eq "3" "$(./kvist eval examples/collections/sequence-helpers.kvist '(indexed-in-place-second)')" "indexed-in-place-second"
assert_eq "2" "$(./kvist eval examples/collections/sequence-helpers.kvist '(filtered-in-place-count)')" "filtered-in-place-count"
assert_eq "1" "$(./kvist eval examples/collections/sequence-helpers.kvist '(removed-in-place-first)')" "removed-in-place-first"
assert_eq "4" "$(./kvist eval examples/collections/sequence-helpers.kvist '(kept-in-place-first)')" "kept-in-place-first"
assert_eq "10" "$(./kvist eval examples/collections/sequence-helpers.kvist '(appended-total)')" "appended-total"
assert_eq "6" "$(./kvist eval examples/collections/sequence-helpers.kvist '(copied-total)')" "copied-total"
assert_eq "6" "$(./kvist eval examples/collections/sequence-helpers.kvist '(distinct-total)')" "distinct-total"
assert_eq "2" "$(./kvist eval examples/collections/sequence-helpers.kvist '(first-per-parity-count)')" "first-per-parity-count"
assert_eq "1" "$(./kvist eval examples/collections/sequence-helpers.kvist '(ragged-chunk-size)')" "ragged-chunk-size"
assert_eq "4" "$(./kvist eval examples/collections/sequence-helpers.kvist '(run-count)')" "run-count"
assert_eq "15" "$(./kvist eval examples/collections/sequence-helpers.kvist '(flattened-total)')" "flattened-total"
assert_eq "4" "$(./kvist eval examples/collections/sequence-helpers.kvist '(threaded-first)')" "threaded-first"
assert_eq "/health" "$(./kvist eval examples/language/declarations.kvist '(endpoint-summary)')" "endpoint-summary"
assert_eq "404" "$(./kvist eval examples/language/declarations.kvist '(shorthand-status-code)')" "shorthand-status-code"
assert_eq "36" "$(./kvist eval examples/collections/sequences.kvist '(age-for-ada)')" "age-for-ada"
assert_eq "3" "$(./kvist eval examples/collections/sequences.kvist '(status-run-count)')" "status-run-count"
assert_eq "2" "$(./kvist eval examples/collections/sequences.kvist '(active-status-group-count)')" "active-status-group-count"
assert_eq "2" "$(./kvist eval examples/language/data-literals.kvist '(temp-buffer-len)')" "temp-buffer-len"
assert_eq "3" "$(./kvist eval examples/language/data-literals.kvist '(temp-scoped-buffer-len)')" "temp-scoped-buffer-len"
assert_eq "1500" "$(./kvist eval examples/interop/core/core-time-slice.kvist '(duration-ms)')" "duration-ms"
assert_eq "2" "$(./kvist eval examples/interop/core/core-time-slice.kvist '(fixed-date-weekday)')" "fixed-date-weekday"
assert_eq "10" "$(./kvist eval examples/interop/core/core-time-slice.kvist '(fixed-date-string-length)')" "fixed-date-string-length"
assert_eq "17" "$(./kvist eval examples/interop/core/core-time-slice.kvist '(min-max-score)')" "min-max-score"
assert_eq "2" "$(./kvist eval examples/interop/core/core-time-slice.kvist '(search-score)')" "search-score"
assert_eq "49" "$(./kvist eval examples/interop/core/core-concurrency.kvist '(future-like-square)')" "future-like-square"
assert_eq "2" "$(./kvist eval examples/interop/core/core-concurrency.kvist '(mutex-protected-count)')" "mutex-protected-count"
assert_eq "30" "$(./kvist eval examples/interop/core/core-container-queue.kvist '(fifo-total)')" "fifo-total"
assert_eq "60" "$(./kvist eval examples/interop/core/core-container-queue.kvist '(deque-score)')" "deque-score"
assert_eq "5" "$(./kvist eval examples/interop/core/core-container-queue.kvist '(safe-pop-score)')" "safe-pop-score"
assert_eq "5" "$(./kvist eval examples/interop/core/core-paths.kvist '(slash-route-name-len)')" "slash-route-name-len"
assert_eq "16" "$(./kvist eval examples/interop/core/core-paths.kvist '(slash-clean-score)')" "slash-clean-score"
assert_eq "15" "$(./kvist eval examples/interop/core/core-paths.kvist '(filepath-relative-len)')" "filepath-relative-len"
assert_eq "3" "$(./kvist eval examples/interop/core/core-paths.kvist '(filepath-extension-len)')" "filepath-extension-len"
assert_eq "65" "$(./kvist eval examples/interop/core/core-encoding-formats.kvist '(csv-age-total)')" "csv-age-total"
assert_eq "3" "$(./kvist eval examples/interop/core/core-encoding-formats.kvist '(csv-record-count)')" "csv-record-count"
assert_eq "8080" "$(./kvist eval examples/interop/core/core-encoding-formats.kvist '(ini-port)')" "ini-port"
assert_eq "2" "$(./kvist eval examples/interop/core/core-encoding-formats.kvist '(ini-pair-count)')" "ini-pair-count"
parallel_eval_output=$(
    printf '%s\n' \
        '(duration-ms)' \
        '(fixed-date-weekday)' \
        '(fixed-date-string-length)' \
        '(min-max-score)' \
        '(search-score)' |
        xargs -P 5 -I FORM ./kvist eval examples/interop/core/core-time-slice.kvist FORM |
        sort
)
parallel_eval_expected=$(printf '10\n1500\n17\n2\n2')
assert_eq "$parallel_eval_expected" "$parallel_eval_output" "parallel eval output"
assert_eq "parsed 1" "$(./kvist eval examples/interop/core/error-handling.kvist "(parse-label \"one\")")" "parse-label"
assert_eq "not parsed" "$(./kvist eval examples/interop/core/error-handling.kvist "(parse-label \"missing\")")" "parse-label-missing"
assert_eq "3" "$(./kvist eval examples/interop/core/error-handling.kvist "(parsed-total \"one\" \"two\")")" "parsed-total"
assert_eq "0" "$(./kvist eval examples/interop/core/error-handling.kvist "(read-byte-count \"tmp/does-not-exist.txt\")")" "read-byte-count-missing"
tap_age_output=$(./kvist eval examples/collections/tap.kvist '(inspected-age)')
tap_age_expected=$(printf 'user: User{name = "Ada", age = 36}\nage: 36\n36')
assert_eq "$tap_age_expected" "$tap_age_output" "inspected-age"
assert_eq "-1" "$(./kvist eval examples/language/data-literals.kvist '(lookup-missing-default)')" "lookup-missing-default"
assert_eq "51" "$(./kvist eval examples/language/data-literals.kvist '(merged-lookup-total)')" "merged-lookup-total"
assert_eq "51" "$(./kvist eval examples/language/data-literals.kvist '(merge-in-place-total)')" "merge-in-place-total"
assert_eq "Lin" "$(./kvist eval examples/collections/sequences.kvist '(youngest-user-name)')" "youngest-user-name"
assert_eq "Lin" "$(./kvist eval examples/collections/sequences.kvist '(youngest-user-name-in-place)')" "youngest-user-name-in-place"

printf 'tooling: eval check command\n'
./kvist eval examples/collections/higher-order.kvist '(threaded-total)' --check

printf 'tooling: eval declaration form\n'
cat > "$tmp_dir/decl-eval.kvist" <<'EOF'
(package main)
(import "core:fmt")

(defstruct Greeting {
  :message string
})

(proc main []
  (fmt.println "hello"))
EOF
./kvist eval "$tmp_dir/decl-eval.kvist" '(defstruct Greeting { :message string })' --check
./kvist eval "$tmp_dir/decl-eval.kvist" '(import "core:fmt")' --check
./kvist eval "$tmp_dir/decl-eval.kvist" '(proc main [] (fmt.println "hello"))' --check

printf 'tooling: eval odin diagnostic mapping\n'
if ./kvist eval examples/collections/higher-order.kvist '(+ 1 "bad")' --check >"$tmp_dir/bad-eval-check.out" 2>"$tmp_dir/bad-eval-check.err"; then
    printf 'failed: bad eval check unexpectedly succeeded\n' >&2
    exit 1
fi
if ! grep -q 'examples/collections/higher-order.kvist:<eval>:1:1 Error: Cannot convert' "$tmp_dir/bad-eval-check.err"; then
    printf 'failed: bad eval check diagnostic did not point at <eval>\n' >&2
    cat "$tmp_dir/bad-eval-check.err" >&2
    exit 1
fi
if ./kvist eval examples/collections/higher-order.kvist '(let [x: int "bad"] x)' --check >"$tmp_dir/bad-eval-let-check.out" 2>"$tmp_dir/bad-eval-let-check.err"; then
    printf 'failed: bad eval let check unexpectedly succeeded\n' >&2
    exit 1
fi
if ! grep -q 'examples/collections/higher-order.kvist:<eval>:1:14 Error: Cannot convert' "$tmp_dir/bad-eval-let-check.err"; then
    printf 'failed: bad eval let check diagnostic did not point at binding value\n' >&2
    cat "$tmp_dir/bad-eval-let-check.err" >&2
    exit 1
fi

printf 'tooling: legacy eval compile path\n'
./kvist examples/collections/higher-order.kvist --eval '(threaded-total)' -o "$tmp_dir/legacy-eval.odin"
legacy_output=$(odin run "$tmp_dir/legacy-eval.odin" -file)
assert_eq "6" "$legacy_output" "legacy eval output"

printf 'tooling: eval diagnostics\n'
if ./kvist eval examples/collections/higher-order.kvist '(not 1 2)' >"$tmp_dir/bad.out" 2>"$tmp_dir/bad.err"; then
    printf 'failed: bad eval unexpectedly succeeded\n' >&2
    exit 1
fi
if ! grep -q 'examples/collections/higher-order.kvist:<eval>:1:1: not expects one argument' "$tmp_dir/bad.err"; then
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
           (byte-compile-file "emacs/kvist-mode.el")
           (load-file "emacs/kvist-mode.el")
           (byte-compile-file "emacs/kvist-eval.el"))'
    rm -f emacs/kvist-mode.elc emacs/kvist-eval.elc

    printf 'tooling: emacs keybindings and eval comment\n'
    KVIST_CACHE_DIR="$tmp_dir/emacs-cache" emacs -Q --batch --eval \
        "(progn
           (defvar clojure-mode-map (make-sparse-keymap))
           (defvar cider-mode nil)
           (defvar clj-refactor-mode nil)
           (define-derived-mode clojure-mode prog-mode \"Clojure\")
           (defun clojure--put-indentation-spec (&rest _args) nil)
           (provide (quote clojure-mode))
           (add-to-list (quote load-path) \"emacs\")
           (require (quote kvist-eval))
           (let ((file (make-temp-file (expand-file-name \".kvist-emacs-test-\" default-directory) nil \".kvist\")))
             (unwind-protect
                 (progn
                   (with-temp-file file
                     (insert \"(package main)\\n(import \\\"core:fmt\\\")\\n\\n// Adds two ints.\\n(defn add [a: int, b: int] -> int\\n  (+ a b))\\n\\n(defn add-two [a: int, b: int] -> int\\n  (add a b))\\n\\n(defn main []\\n  (fmt.println \\\"from main\\\"))\\n\\n(comment\\n  (add 1 2)\\n  (add-two 1 2)\\n  (with-allocator [allocator context.temp_allocator]\\n    (add 2 1))\\n  (if-ok [value err (read)] value 0)\\n  (main))\\n\"))
                   (find-file file)
                   (kvist-mode)
                   (setq kvist-test-source-buffer (current-buffer))
                   (let ((diagnostic-buffer (kvist--prepare-diagnostic-buffer kvist-result-buffer-name)))
                     (with-current-buffer diagnostic-buffer
                       (let ((inhibit-read-only t)
                             (buffer-read-only nil))
                         (insert file \":6:4 Error: simulated diagnostic\\n\")
                         (insert file \":<eval>:1:14 Error: simulated eval diagnostic\\n\")
                         (kvist--finish-output-buffer t))
                       (unless (eq major-mode (quote compilation-mode))
                         (error \"Expected Kvist diagnostic buffer to use compilation-mode\"))
                       (goto-char (point-min))
                       (let ((msg (compilation-next-error 1)))
                         (unless msg
                           (error \"Expected compilation-next-error to find Kvist diagnostic\")))))
                   (unless (eq (key-binding (kbd \"M-.\")) (quote xref-find-definitions))
                     (error \"Missing M-. xref binding\"))
                   (let ((symbols (kvist--symbols)))
                     (unless (seq-find (lambda (sym) (equal (plist-get sym :name) \"add\")) symbols)
                       (error \"Expected add in kvist symbols: %S\" symbols)))
                   (let ((docs (kvist--symbol-doc-candidates \"add\")))
                     (unless (and docs (equal (plist-get (car docs) :doc) \"Adds two ints.\"))
                       (error \"Expected add docs, got: %S\" docs)))
                   (let ((docs (kvist--symbol-doc-candidates \"fmt.println\")))
                     (unless docs
                       (error \"Expected fmt.println docs\")))
                   (let ((docs (kvist--symbol-doc-candidates \"if-ok\")))
                     (unless (and docs (string-match-p \"zero error value\" (plist-get (car docs) :doc)))
                       (error \"Expected if-ok built-in docs, got: %S\" docs)))
                   (with-temp-buffer
                     (insert \"/*\\n * Block docs.\\n * More docs.\\n */\\nthing :: proc() {}\\n\")
                     (goto-char (point-min))
                     (search-forward \"thing ::\")
                     (let ((doc (kvist--preceding-odin-doc (line-beginning-position))))
                       (unless (equal doc \"Block docs.\\nMore docs.\")
                         (error \"Expected block docs, got: %S\" doc))))
                   (with-temp-buffer
                     (kvist-mode)
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
                   (call-interactively (quote kvist-doc-at-point))
                   (let ((doc-text (with-current-buffer kvist-doc-buffer-name
                                     (buffer-substring-no-properties (point-min) (point-max)))))
                     (unless (string-match-p \"Adds two ints\" doc-text)
                       (error \"Expected displayed add docs, got: %s\" doc-text)))
                   (goto-char (point-min))
                   (search-forward \"if-ok\")
                   (call-interactively (quote kvist-doc-at-point))
                   (let ((doc-text (with-current-buffer kvist-doc-buffer-name
                                     (buffer-substring-no-properties (point-min) (point-max)))))
                     (unless (string-match-p \"zero error value\" doc-text)
                       (error \"Expected displayed if-ok docs, got: %s\" doc-text)))
                   (let ((defs (xref-backend-definitions (quote kvist) \"add\")))
                     (unless defs
                       (error \"Expected xref definition for add\")))
                   (goto-char (point-min))
                   (search-forward \"(add-two 1 2)\")
                   (backward-char 7)
                   (unless (equal (kvist--identifier-at-point) \"add-two\")
                     (error \"Expected add-two identifier, got: %S\" (kvist--identifier-at-point)))
                   (let ((defs (xref-backend-definitions (quote kvist) (kvist--identifier-at-point))))
                     (unless defs
                       (error \"Expected xref definition for same-file hyphenated proc\")))
                   (let ((defs (xref-backend-definitions (quote kvist) \"map\")))
                     (unless (and defs (string-match-p \"src/kvist/emit\\\\.odin\" (format \"%S\" defs)))
                       (error \"Expected implementation xref for Kvist helper map, got: %S\" defs)))
                   (let ((defs (xref-backend-definitions (quote kvist) \"proc\")))
                     (unless (and defs (string-match-p \"src/kvist/parse\\\\.odin\" (format \"%S\" defs)))
                       (error \"Expected implementation xref for Kvist form proc, got: %S\" defs)))
                   (let ((defs (xref-backend-definitions (quote kvist) \"fmt.println\")))
                     (unless defs
                       (error \"Expected xref definition for fmt.println\")))
                   (let ((candidates (kvist--completion-candidates)))
                     (unless (and (member \"add\" candidates)
                                  (member \"proc\" candidates)
                                  (member \"map\" candidates)
                                  (member \"fmt.println\" candidates))
                       (error \"Expected completion candidates, got: %S\" candidates)))
                   (dolist (binding (list (cons \"C-c C-e\" (quote kvist-eval-form-at-point))
                                          (cons \"C-c C-c\" (quote kvist-eval-top-level-form))
                                          (cons \"C-c C-i\" (quote kvist-insert-form-result))
                                          (cons \"C-c C-.\" (quote kvist-doc-at-point))
                                          (cons \"C-c C-k\" (quote kvist-eval-buffer))
                                          (cons \"C-c C-v\" (quote kvist-check-buffer))
                                          (cons \"C-c C-b\" (quote kvist-build-buffer))
                                          (cons \"C-c C-m\" (quote kvist-expand-form-at-point))
                                          (cons \"C-c M-m\" (quote kvist-macroexpand-form-at-point))
                                          (cons \"C-c C-w\" (quote kvist-save-form-result))
                                          (cons \"C-c C-l\" (quote kvist-cache-list))
                                          (cons \"C-c C-o\" (quote kvist-cache-open))
                                          (cons \"C-c C-d\" (quote kvist-cache-rm))))
                     (unless (eq (key-binding (kbd (car binding))) (cdr binding))
                       (error \"Missing binding %s\" (car binding))))
                   (goto-char (point-min))
                   (search-forward \"  (with-allocator\")
                   (beginning-of-line)
                   (skip-chars-forward \" \\t\")
                   (let* ((bounds (kvist--form-bounds-at-point))
                          (form (buffer-substring-no-properties (car bounds) (cdr bounds))))
                     (unless (string-prefix-p \"(with-allocator\" form)
                       (error \"Expected with-allocator form, got: %s\" form)))
                   (call-interactively (quote kvist-macroexpand-form-at-point))
                   (let ((macro-text (with-current-buffer kvist-macroexpand-buffer-name
                                       (buffer-substring-no-properties (point-min) (point-max)))))
                     (unless (string-match-p \"context\\\\.allocator allocator\" macro-text)
                       (error \"Expected macroexpand allocator set, got: %s\" macro-text)))
                   (goto-char (point-min))
                   (search-forward \"(add 1 2)\")
                   (call-interactively (quote kvist-expand-form-at-point))
                   (with-current-buffer kvist-generated-buffer-name
                     (goto-char (point-min))
                     (unless (search-forward \"fmt.println(add(1, 2))\" nil t)
                       (error \"Expected generated eval wrapper\")))
                   (goto-char (point-min))
                   (search-forward \"(add 1 2)\")
                   (call-interactively (quote kvist-insert-form-result))
                   (goto-char (point-min))
                   (unless (search-forward \";; => 3\" nil t)
                     (error \"Expected inserted eval comment\"))
                   (goto-char (point-min))
                   (search-forward \"(add 1 2)\")
                   (kvist-save-form-result \"emacs-sum\")
                   (let ((cache-path (expand-file-name \"emacs-sum\" \"$tmp_dir/emacs-cache\")))
                     (unless (file-exists-p cache-path)
                       (error \"Expected saved eval cache file\"))
                     (with-temp-buffer
                       (insert-file-contents cache-path)
                       (unless (equal (buffer-string) \"3\\n\")
                         (error \"Expected saved eval cache content\"))))
                   (kvist-cache-list)
                   (let ((cache-list (with-current-buffer kvist-result-buffer-name
                                       (buffer-substring-no-properties (point-min) (point-max)))))
                     (unless (string-match-p \"emacs-sum\" cache-list)
                       (error \"Expected saved eval cache listing\")))
                   (kvist-cache-rm \"emacs-sum\")
                   (when (file-exists-p (expand-file-name \"emacs-sum\" \"$tmp_dir/emacs-cache\"))
                     (error \"Expected removed eval cache file\"))
                   (let ((source-buffer kvist-test-source-buffer))
                     (set-buffer source-buffer)
                     (goto-char (point-min))
                     (search-forward \"(+ a b)\")
                     (delete-region (line-beginning-position) (line-end-position))
                     (insert \"  (+ a \\\"bad\\\"))\")
                     (save-buffer)
                     (call-interactively (quote kvist-check-buffer))
                     (with-current-buffer kvist-result-buffer-name
                       (unless (eq major-mode (quote compilation-mode))
                         (error \"Expected failed check buffer to use compilation-mode\"))
                       (goto-char (point-min))
                       (unless (search-forward \".kvist:\" nil t)
                         (error \"Expected failed check to contain Kvist diagnostic\"))
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
                       (error \"Expected next-error from source to stay in Kvist source buffer\"))
                     (unless (= (line-number-at-pos) 6)
                       (error \"Expected next-error from source to jump to diagnostic line, got %s\"
                              (line-number-at-pos)))
                     (unless (eq next-error-last-buffer (get-buffer kvist-result-buffer-name))
                       (error \"Expected Kvist result buffer to be the active next-error buffer\"))
                     (set-buffer source-buffer)
                     (goto-char (point-min))
                     (search-forward \"(+ a \\\"bad\\\")\")
                     (delete-region (line-beginning-position) (line-end-position))
                     (insert \"  (+ a b))\")
                     (save-buffer))
                   (set-buffer kvist-test-source-buffer)
                   (goto-char (point-min))
                   (search-forward \"(main)\")
                   (call-interactively (quote kvist-insert-form-result))
                   (goto-char (point-min))
                   (unless (search-forward \";; => from main\" nil t)
                     (error \"Expected inserted void-call eval comment\")))
               (ignore-errors (kill-buffer (current-buffer)))
               (delete-file file))))"
else
    printf 'tooling: emacs not found, skipping byte compile\n'
fi

printf 'tooling integration ok\n'
