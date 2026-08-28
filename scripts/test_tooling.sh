#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

odin build src/cli/kvist -o:speed
PATH="$ROOT:$PATH"
export PATH

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

./kvist compile examples/collections/higher-order.kvist \
  -o "$tmp_dir/split.odin" \
  --map "$tmp_dir/split.map" \
  --packages
assert_file_nonempty "$tmp_dir/split.odin" "split compile root output"
assert_file_nonempty "$tmp_dir/split.map" "split compile root source map"
if [ "$(find "$tmp_dir/split.odin.packages" -type f -name 'package.odin' | wc -l | tr -d ' ')" -lt 2 ] ||
   [ "$(find "$tmp_dir/split.map.packages" -type f -name '*.map' | wc -l | tr -d ' ')" -lt 2 ]; then
    printf 'failed: split compile did not emit package Odin and source-map artifacts\n' >&2
    exit 1
fi
odin check "$tmp_dir/split.odin" -file

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

printf 'tooling: editor symbol commands\n'
./kvist editor-symbols examples/collections/log-source.kvist log-lines > "$tmp_dir/editor-symbols.tsv"
if ! grep -q "$(printf 'iterator\tlog-lines')" "$tmp_dir/editor-symbols.tsv"; then
    printf 'failed: editor-symbols output did not include log-lines iterator\n' >&2
    cat "$tmp_dir/editor-symbols.tsv" >&2
    exit 1
fi
if ! grep -q 'log-source.kvist' "$tmp_dir/editor-symbols.tsv"; then
    printf 'failed: editor-symbols output did not include source file\n' >&2
    cat "$tmp_dir/editor-symbols.tsv" >&2
    exit 1
fi

./kvist lookup examples/collections/log-source.kvist log-lines > "$tmp_dir/lookup.tsv"
if ! grep -q "$(printf 'iterator\tlog-lines')" "$tmp_dir/lookup.tsv"; then
    printf 'failed: lookup output did not include log-lines iterator\n' >&2
    cat "$tmp_dir/lookup.tsv" >&2
    exit 1
fi

./kvist complete examples/collections/log-source.kvist log > "$tmp_dir/complete.tsv"
if ! grep -q "$(printf 'iterator\tlog-lines')" "$tmp_dir/complete.tsv"; then
    printf 'failed: complete output did not include log-lines iterator\n' >&2
    cat "$tmp_dir/complete.tsv" >&2
    exit 1
fi

./kvist doc examples/collections/log-source.kvist log-lines > "$tmp_dir/doc.txt"
if ! grep -q 'iterator log-lines' "$tmp_dir/doc.txt"; then
    printf 'failed: doc output did not include log-lines heading\n' >&2
    cat "$tmp_dir/doc.txt" >&2
    exit 1
fi
if ! grep -q '(log-lines \[lines: \[\]string\] -> Log_Source :yield string)' "$tmp_dir/doc.txt"; then
    printf 'failed: doc output did not include iterator signature\n' >&2
    cat "$tmp_dir/doc.txt" >&2
    exit 1
fi

./kvist xref examples/collections/log-source.kvist log-lines > "$tmp_dir/xref.txt"
if ! grep -q "$(printf 'log-source.kvist:26:10\titerator\tlog-lines')" "$tmp_dir/xref.txt"; then
    printf 'failed: xref output did not point at log-lines definition\n' >&2
    cat "$tmp_dir/xref.txt" >&2
    exit 1
fi

./kvist imported-symbols examples/collections/sequences.kvist > "$tmp_dir/imported-symbols.tsv"
if ! grep -q "$(printf 'kvist package\tarr.map')" "$tmp_dir/imported-symbols.tsv"; then
    printf 'failed: imported-symbols output did not include arr.map\n' >&2
    cat "$tmp_dir/imported-symbols.tsv" >&2
    exit 1
fi

./kvist package-symbols kvist:arr arr > "$tmp_dir/package-symbols.tsv"
if ! grep -q "$(printf 'macro\tarr.map')" "$tmp_dir/package-symbols.tsv"; then
    printf 'failed: package-symbols output did not include arr.map\n' >&2
    cat "$tmp_dir/package-symbols.tsv" >&2
    exit 1
fi

printf 'tooling: check command\n'
./kvist check examples/language/hello.kvist --generated "$tmp_dir/check.odin"
assert_file_nonempty "$tmp_dir/check.odin" "check generated output"

printf 'tooling: frontend check command\n'
frontend_cache_dir="$tmp_dir/frontend-cache"
KVIST_CACHE_DIR="$frontend_cache_dir" ./kvist frontend-check examples/language/hello.kvist \
  --timings-json "$tmp_dir/frontend-cold-timings.json"
KVIST_CACHE_DIR="$frontend_cache_dir" ./kvist frontend-check examples/language/hello.kvist \
  --timings-json "$tmp_dir/frontend-warm-timings.json"
if ! grep -q '"command":"frontend-check"' "$tmp_dir/frontend-cold-timings.json" ||
   ! grep -q '"cache_status":"miss"' "$tmp_dir/frontend-cold-timings.json" ||
   ! grep -q '"process_ms":0.0000000000000000' "$tmp_dir/frontend-cold-timings.json" ||
   ! grep -q '"cache_status":"hit"' "$tmp_dir/frontend-warm-timings.json" ||
   grep -q '"frontend":' "$tmp_dir/frontend-warm-timings.json"; then
    printf 'failed: frontend-check did not use the frontend cache without Odin\n' >&2
    cat "$tmp_dir/frontend-cold-timings.json" >&2
    cat "$tmp_dir/frontend-warm-timings.json" >&2
    exit 1
fi

printf 'tooling: phase timings\n'
./kvist compile examples/language/hello.kvist \
  -o "$tmp_dir/timed.odin" \
  --timings \
  --timings-json "$tmp_dir/compile-timings.json" \
  >"$tmp_dir/timed-compile.out" \
  2>"$tmp_dir/timed-compile.err"
assert_file_nonempty "$tmp_dir/compile-timings.json" "compile timing JSON"
if [ -s "$tmp_dir/timed-compile.out" ]; then
    printf 'failed: timed compile polluted stdout\n' >&2
    cat "$tmp_dir/timed-compile.out" >&2
    exit 1
fi
if ! grep -q 'Kvist timings (compile, success)' "$tmp_dir/timed-compile.err" ||
   ! grep -q '"schema_version":1' "$tmp_dir/compile-timings.json" ||
   ! grep -q '"name":"macro_expansion"' "$tmp_dir/compile-timings.json"; then
    printf 'failed: compile timing report was incomplete\n' >&2
    cat "$tmp_dir/timed-compile.err" >&2
    cat "$tmp_dir/compile-timings.json" >&2
    exit 1
fi

./kvist run examples/language/hello.kvist \
  --timings-json "$tmp_dir/run-timings.json" \
  >"$tmp_dir/timed-run.out" \
  2>"$tmp_dir/timed-run.err"
assert_eq "hello from kvist" "$(cat "$tmp_dir/timed-run.out")" "timed run stdout"
if ! grep -q '"detail_available":true' "$tmp_dir/run-timings.json" ||
   ! grep -q '"execution_ms":' "$tmp_dir/run-timings.json"; then
    printf 'failed: run timing report lacked Odin or execution detail\n' >&2
    cat "$tmp_dir/run-timings.json" >&2
    exit 1
fi

printf 'tooling: content-addressed compile cache\n'
compile_cache_dir="$tmp_dir/compile-cache"
mkdir -p "$tmp_dir/cache-package/support"
cat > "$tmp_dir/cache-package/support/support.kvist" <<'EOF'
(package support)
(def answer 41)
EOF
cat > "$tmp_dir/cache-package/main.kvist" <<'EOF'
(package main)
(import support "support")
(defn main []
  (println support.answer))
EOF
KVIST_CACHE_DIR="$compile_cache_dir" ./kvist check "$tmp_dir/cache-package/main.kvist" \
  --timings-json "$tmp_dir/cache-cold-timings.json"
first_cache_count=$(find "$compile_cache_dir/compile-packages" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_eq "1" "$first_cache_count" "initial compile cache entry count"
KVIST_CACHE_DIR="$compile_cache_dir" ./kvist check "$tmp_dir/cache-package/main.kvist" \
  --timings-json "$tmp_dir/cache-warm-timings.json"
warm_cache_count=$(find "$compile_cache_dir/compile-packages" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_eq "1" "$warm_cache_count" "warm compile cache entry count"
if ! grep -q '"fingerprint_cache_status":"miss"' "$tmp_dir/cache-cold-timings.json" ||
   ! grep -q '"fingerprint_files_hashed":' "$tmp_dir/cache-cold-timings.json" ||
   ! grep -q '"fingerprint_cache_status":"hit"' "$tmp_dir/cache-warm-timings.json" ||
   ! grep -q '"fingerprint_files_hashed":0' "$tmp_dir/cache-warm-timings.json" ||
   ! grep -q '"dependency_discovery_ms":0.0000000000000000' "$tmp_dir/cache-warm-timings.json"; then
    printf 'failed: dependency fingerprint cache did not reuse the unchanged graph\n' >&2
    cat "$tmp_dir/cache-cold-timings.json" >&2
    cat "$tmp_dir/cache-warm-timings.json" >&2
    exit 1
fi
KVIST_CACHE_DIR="$compile_cache_dir" ./kvist check "$tmp_dir/cache-package/main.kvist" \
  --timings-json "$tmp_dir/cache-hit-timings.json"
if ! grep -q '"cache_status":"hit"' "$tmp_dir/cache-hit-timings.json" ||
   grep -q '"frontend":' "$tmp_dir/cache-hit-timings.json"; then
    printf 'failed: cache-hit timing report was incorrect\n' >&2
    cat "$tmp_dir/cache-hit-timings.json" >&2
    exit 1
fi
cat > "$tmp_dir/cache-package/main.kvist" <<'EOF'
(package main)
(import support "support")
(defn main []
  (println (+ support.answer 0)))
EOF
KVIST_CACHE_DIR="$compile_cache_dir" ./kvist check "$tmp_dir/cache-package/main.kvist" \
  --timings-json "$tmp_dir/cache-root-changed-timings.json"
if ! grep -q '"cache_status":"miss"' "$tmp_dir/cache-root-changed-timings.json" ||
   ! grep -Eq '"packages_reused":[1-9]' "$tmp_dir/cache-root-changed-timings.json" ||
   ! grep -Eq '"packages_emitted":[1-9]' "$tmp_dir/cache-root-changed-timings.json"; then
    printf 'failed: root-only edit did not reuse imported package frontend artifacts\n' >&2
    cat "$tmp_dir/cache-root-changed-timings.json" >&2
    exit 1
fi
cat > "$tmp_dir/cache-package/support/support.kvist" <<'EOF'
(package support)
(def answer 42)
EOF
KVIST_CACHE_DIR="$compile_cache_dir" ./kvist check "$tmp_dir/cache-package/main.kvist" \
  --timings-json "$tmp_dir/cache-file-changed-timings.json"
changed_cache_count=$(find "$compile_cache_dir/compile-packages" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_eq "3" "$changed_cache_count" "dependency-invalidated compile cache entry count"
if ! grep -q '"fingerprint_cache_status":"miss"' "$tmp_dir/cache-file-changed-timings.json" ||
   ! grep -q '"fingerprint_files_hashed":1' "$tmp_dir/cache-file-changed-timings.json" ||
   grep -q '"fingerprint_files_reused":0' "$tmp_dir/cache-file-changed-timings.json"; then
    printf 'failed: changed dependency did not selectively rebuild the fingerprint manifest\n' >&2
    cat "$tmp_dir/cache-file-changed-timings.json" >&2
    exit 1
fi
cat > "$tmp_dir/cache-package/support/extra.kvist" <<'EOF'
(package support)
(def extra 1)
EOF
KVIST_CACHE_DIR="$compile_cache_dir" ./kvist check "$tmp_dir/cache-package/main.kvist" \
  --timings-json "$tmp_dir/cache-directory-changed-timings.json"
directory_changed_cache_count=$(find "$compile_cache_dir/compile-packages" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_eq "4" "$directory_changed_cache_count" "dependency-directory-invalidated compile cache entry count"
if ! grep -q '"fingerprint_cache_status":"miss"' "$tmp_dir/cache-directory-changed-timings.json" ||
   ! grep -q '"fingerprint_files_hashed":1' "$tmp_dir/cache-directory-changed-timings.json" ||
   grep -q '"fingerprint_files_reused":0' "$tmp_dir/cache-directory-changed-timings.json"; then
    printf 'failed: added package file did not selectively rebuild the fingerprint manifest\n' >&2
    cat "$tmp_dir/cache-directory-changed-timings.json" >&2
    exit 1
fi

printf 'tooling: dependency-specific package invalidation\n'
dependency_cache_dir="$tmp_dir/dependency-cache"
mkdir -p \
  "$tmp_dir/dependency-package/a" \
  "$tmp_dir/dependency-package/b" \
  "$tmp_dir/dependency-package/c"
cat > "$tmp_dir/dependency-package/main.kvist" <<'EOF'
(package main)
(import a "a")
(import b "b")
(defn main []
  (println a.answer b.answer))
EOF
cat > "$tmp_dir/dependency-package/a/a.kvist" <<'EOF'
(package a)
(import c "../c")
(def answer c.answer)
EOF
cat > "$tmp_dir/dependency-package/b/b.kvist" <<'EOF'
(package b)
(def answer 7)
EOF
cat > "$tmp_dir/dependency-package/c/c.kvist" <<'EOF'
(package c)
(def answer 41)
EOF
KVIST_CACHE_DIR="$dependency_cache_dir" \
  ./kvist check "$tmp_dir/dependency-package/main.kvist"
cat > "$tmp_dir/dependency-package/c/c.kvist" <<'EOF'
(package c)
(def answer 42)
EOF
KVIST_CACHE_DIR="$dependency_cache_dir" \
  ./kvist check "$tmp_dir/dependency-package/main.kvist" \
  --timings-json "$tmp_dir/dependency-interface-change.json"
if ! grep -q '"packages_reused":2' "$tmp_dir/dependency-interface-change.json" ||
   ! grep -q '"packages_emitted":3' "$tmp_dir/dependency-interface-change.json"; then
    printf 'failed: dependency interface change did not preserve unrelated package artifacts\n' >&2
    cat "$tmp_dir/dependency-interface-change.json" >&2
    exit 1
fi

prune_cache_dir="$tmp_dir/prune-cache"
mkdir -p "$prune_cache_dir/compile-packages"
touch "$prune_cache_dir/compile-packages/legacy-graph.json"
for entry in $(seq 1 65); do
    mkdir "$prune_cache_dir/compile-packages/stale-$entry"
done
KVIST_CACHE_DIR="$prune_cache_dir" ./kvist check examples/language/hello.kvist
pruned_graph_count=$(find "$prune_cache_dir/compile-packages" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
assert_eq "64" "$pruned_graph_count" "bounded package graph cache entry count"

secondary_cache_dir="$tmp_dir/secondary-prune-cache"
KVIST_CACHE_DIR="$secondary_cache_dir" ./kvist check "$tmp_dir/cache-package/main.kvist"
frontend_active_dir=$(find "$secondary_cache_dir/package-frontend" -mindepth 1 -maxdepth 1 -type d | head -n 1)
for entry in $(seq 1 513); do
    touch "$frontend_active_dir/stale-$entry.json"
done
cat >> "$tmp_dir/cache-package/main.kvist" <<'EOF'
;; force a graph-cache miss so frontend pruning runs
EOF
KVIST_CACHE_DIR="$secondary_cache_dir" ./kvist check "$tmp_dir/cache-package/main.kvist"
frontend_entry_count=$(find "$frontend_active_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
assert_eq "512" "$frontend_entry_count" "bounded package frontend cache entry count"

for entry in $(seq 1 257); do
    touch "$secondary_cache_dir/fingerprints/stale-$entry.json"
done
cat >> "$tmp_dir/cache-package/main.kvist" <<'EOF'
;; force fingerprint publication and pruning
EOF
KVIST_CACHE_DIR="$secondary_cache_dir" ./kvist check "$tmp_dir/cache-package/main.kvist"
fingerprint_entry_count=$(find "$secondary_cache_dir/fingerprints" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
assert_eq "256" "$fingerprint_entry_count" "bounded fingerprint cache entry count"

printf 'tooling: check standalone file beside raw Odin programs\n'
./kvist check benchmarks/aggregate_helpers.kvist

printf 'tooling: check diagnostic mapping\n'
cat > "$tmp_dir/bad.kvist" <<'EOF'
(package main)
(import fmt "core:fmt")

(defn main []
  (let [x: int "bad"]
    (fmt.println x)))
EOF
if ./kvist check "$tmp_dir/bad.kvist" >"$tmp_dir/bad-check.out" 2>"$tmp_dir/bad-check.err"; then
    printf 'failed: bad check unexpectedly succeeded\n' >&2
    exit 1
fi
if ./kvist check "$tmp_dir/bad.kvist" \
     --timings-json "$tmp_dir/bad-timings.json" \
     >"$tmp_dir/bad-timed-check.out" \
     2>"$tmp_dir/bad-timed-check.err"; then
    printf 'failed: timed bad check unexpectedly succeeded\n' >&2
    exit 1
fi
if ! grep -q '"success":false' "$tmp_dir/bad-timings.json" ||
   ! grep -q '"process_ms":' "$tmp_dir/bad-timings.json"; then
    printf 'failed: failed check did not publish timing JSON\n' >&2
    cat "$tmp_dir/bad-timings.json" >&2
    exit 1
fi
if ! grep -q "$tmp_dir/bad.kvist:5:16 Error: Cannot convert" "$tmp_dir/bad-check.err"; then
    printf 'failed: bad check diagnostic did not map back to .kvist\n' >&2
    cat "$tmp_dir/bad-check.err" >&2
    exit 1
fi

mkdir -p "$tmp_dir/bad-import/middle" "$tmp_dir/bad-import/support"
cat > "$tmp_dir/bad-import/main.kvist" <<'EOF'
(package main)
(import middle "middle")
(defn main []
  (println middle.answer))
EOF
cat > "$tmp_dir/bad-import/middle/middle.kvist" <<'EOF'
(package middle)
(import support "../support")
(def answer support.answer)
EOF
cat > "$tmp_dir/bad-import/support/support.kvist" <<'EOF'
(package support)
(def answer: int "bad")
EOF
import_diagnostic_cache="$tmp_dir/import-diagnostic-cache"
for pass in cold warm
do
    if KVIST_CACHE_DIR="$import_diagnostic_cache" \
         ./kvist check "$tmp_dir/bad-import/main.kvist" \
         >"$tmp_dir/bad-import-$pass.out" \
         2>"$tmp_dir/bad-import-$pass.err"; then
        printf 'failed: bad transitive import unexpectedly succeeded on %s pass\n' "$pass" >&2
        exit 1
    fi
    if ! grep -q "$tmp_dir/bad-import/support/support.kvist:2:.*Error: Cannot convert" \
         "$tmp_dir/bad-import-$pass.err"; then
        printf 'failed: %s transitive import diagnostic did not map to its Kvist source\n' "$pass" >&2
        cat "$tmp_dir/bad-import-$pass.err" >&2
        exit 1
    fi
done

cat > "$tmp_dir/bad-statements.kvist" <<'EOF'
(package main)

(defn main []
  (return))

(defn if-test [] -> int
  (if "bad"
    1
    0))

(defn when-test []
  (when "bad"
    (return)))

(defn set-test []
  (let [x 1]
    (set! x "bad")))

(defn for-test []
  (for [x 123]
    (return)))

(defn return-test [] -> int
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
    "$tmp_dir/bad-statements.kvist:20:11 Error: Cannot iterate" \
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
tap_output=$(./kvist eval examples/collections/tap.kvist '(tap> "answer" 42)')
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
assert_eq "3 rem 2" "$(./kvist eval examples/language/multi-return-bindings.kvist "(quotient-label 17 5)")" "multi-return-label"
assert_eq "42" "$(./kvist eval examples/language/multi-return-bindings.kvist "(parsed-or-zero \"42\")")" "multi-return-success"
assert_eq "0" "$(./kvist eval examples/language/multi-return-bindings.kvist "(parsed-or-zero \"missing\")")" "multi-return-fallback"
assert_eq "0" "$(./kvist eval examples/interop/core/core-os-paths.kvist "(read-demo-length \"tmp/does-not-exist.txt\")")" "read-demo-missing"
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
(import fmt "core:fmt")

(defstruct Greeting {
  message: string
})

(defn main []
  (fmt.println "hello"))
EOF
./kvist eval "$tmp_dir/decl-eval.kvist" '(defstruct Greeting {message: string})' --check
./kvist eval "$tmp_dir/decl-eval.kvist" '(import fmt "core:fmt")' --check
./kvist eval "$tmp_dir/decl-eval.kvist" '(defn main [] (fmt.println "hello"))' --check

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
           ;; A long-running Emacs preserves the old defvar keymap. Verify
           ;; that reloading repairs core eval and debugger bindings.
           (define-key kvist-eval-mode-map (kbd \"C-c M-f\") nil)
           (define-key kvist-eval-mode-map (kbd \"C-c M-v\") nil)
           (define-key kvist-eval-mode-map
             (kbd \"C-c C-k\") (quote kvist-expand-form-at-point))
           (load-file \"emacs/kvist-eval.el\")
           (kvist--install-debug-keybindings kvist-eval-mode-map)
           (unless (and (eq (lookup-key kvist-eval-mode-map (kbd \"C-c M-f\"))
                            (quote kvist-debug-show-frame))
                        (eq (lookup-key kvist-eval-mode-map (kbd \"C-c M-v\"))
                            (quote kvist-debug-eval-expression))
                        (eq (lookup-key kvist-eval-mode-map (kbd \"C-c C-k\"))
                            (quote kvist-eval-buffer)))
             (error \"Kvist did not repair reloaded eval bindings\"))
           (define-key kvist-debug-source-mode-map
             (kbd \"i\") (quote kvist-debug-step))
           (define-key kvist-debug-source-mode-map (kbd \"n\") nil)
           (define-key kvist-debug-source-mode-map (kbd \"e\") nil)
           (define-key kvist-debug-source-mode-map (kbd \"q\") nil)
           (define-key kvist-debug-source-mode-map
             (kbd \"v\") (quote kvist-debug-eval-expression))
           (kvist--install-debug-source-keybindings
            kvist-debug-source-mode-map)
           (unless
               (and (eq (lookup-key kvist-debug-source-mode-map (kbd \"n\"))
                        (quote kvist-debug-step))
                    (eq (lookup-key kvist-debug-source-mode-map (kbd \"e\"))
                        (quote kvist-debug-eval-expression))
                    (eq (lookup-key kvist-debug-source-mode-map (kbd \"q\"))
                        (quote kvist-debug-abort))
                    (null (lookup-key kvist-debug-source-mode-map (kbd \"i\")))
                    (null (lookup-key kvist-debug-source-mode-map (kbd \"v\"))))
             (error \"Kvist did not repair reloaded source-debug bindings\"))
           (when kvist-repl-auto-start
             (error \"Kvist REPL must require explicit startup by default\"))
           (let ((make-backup-files nil)
                 (kvist-repl-auto-start t)
                 (file (make-temp-file (expand-file-name \".kvist-emacs-test-\" default-directory) nil \".kvist\")))
             (unwind-protect
                 (progn
                   (with-temp-file file
                     (insert \"(package main)\\n(import fmt \\\"core:fmt\\\")\\n(import arr \\\"kvist:arr\\\")\\n(import debug \\\"kvist:debug\\\")\\n(import condition \\\"kvist:condition\\\")\\n\\n;; Adds two ints.\\n(defn add [a: int, b: int] -> int\\n  (+ a b))\\n\\n(defn add-two [a: int, b: int] -> int\\n  (add a b))\\n\\n(defn main []\\n  (fmt.println \\\"from main\\\"))\\n\\n(defn announce []\\n  (fmt.println \\\"announced\\\"))\\n\\n(defstruct Pair {\\n  left: int\\n  right: string\\n})\\n\\n(comment\\n  (add 1 2)\\n  (add-two 1 2)\\n  (with-allocator [allocator context.temp_allocator]\\n    (add 2 1))\\n  (if-ok [value err (read)] value 0)\\n  (Pair {left: 1 right: \\\"two\\\"})\\n  ([dynamic]int [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21])\\n  (map[string]int {\\\"a\\\" 7})\\n  (announce))\\n\"))
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
                   (unless (eq (key-binding (kbd \"C-c C-s\")) (quote kvist-repl-start))
                     (error \"Missing C-c C-s REPL start binding\"))
                   (unless (eq (key-binding (kbd \"C-c C-z\")) (quote kvist-repl))
                     (error \"Missing C-c C-z REPL switch binding\"))
                   (when (eq (key-binding (kbd \"C-c M-j\")) (quote kvist-repl-start))
                     (error \"Kvist must not shadow C-c M-j for REPL startup\"))
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
                     (unless (and docs
                                  (string-match-p \"zero error\" (plist-get (car docs) :doc))
                                  (string-match-p \"value\" (plist-get (car docs) :doc)))
                       (error \"Expected if-ok built-in docs, got: %S\" docs)))
                   (with-temp-buffer
                     (kvist-mode)
                     (insert \";; semi\\nafter-semi\\n// slash\\nafter-slash\\n(code) /* block */ tail\\n\")
                     (font-lock-ensure)
                     (goto-char (point-min))
                     (search-forward \"semi\")
                     (unless (nth 4 (syntax-ppss))
                       (error \"Expected ;; to be comment syntax\"))
                     (search-forward \"after-semi\")
                     (when (nth 4 (syntax-ppss))
                       (error \"Expected ;; comment to end at newline\"))
                     (search-forward \"slash\")
                     (when (nth 4 (syntax-ppss))
                       (error \"Expected // not to be comment syntax\"))
                     (when (eq (get-text-property (point) (quote face)) (quote font-lock-comment-face))
                       (error \"Expected // not to use comment face\"))
                     (search-forward \"after-slash\")
                     (when (nth 4 (syntax-ppss))
                       (error \"Expected // comment to end at newline\"))
                     (search-forward \"block\")
                     (when (nth 4 (syntax-ppss))
                       (error \"Expected /* */ not to be comment syntax\"))
                     (when (eq (get-text-property (point) (quote face)) (quote font-lock-comment-face))
                       (error \"Expected /* */ not to use comment face\"))
                     (search-forward \"tail\")
                     (when (nth 4 (syntax-ppss))
                       (error \"Expected tail not to be comment syntax\")))
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
                     (unless (and (string-match-p \"zero error\" doc-text)
                                  (string-match-p \"value\" doc-text))
                       (error \"Expected displayed if-ok docs, got: %s\" doc-text)))
                   (let ((defs (xref-backend-definitions (quote kvist) \"add\")))
                     (unless defs
                       (error \"Expected xref definition for add\"))
                     (let* ((location (xref-item-location (car defs)))
                            (target (xref-file-location-file location)))
                       (unless (equal (expand-file-name target)
                                      (expand-file-name file))
                         (error \"Same-file xref leaked tooling temp path: %S\"
                                target))))
                   (goto-char (point-min))
                   (search-forward \"(add-two 1 2)\")
                   (backward-char 7)
                   (unless (equal (kvist--identifier-at-point) \"add-two\")
                     (error \"Expected add-two identifier, got: %S\" (kvist--identifier-at-point)))
                   (let ((defs (xref-backend-definitions (quote kvist) (kvist--identifier-at-point))))
                     (unless defs
                       (error \"Expected xref definition for same-file hyphenated defn\"))
                     (let* ((location (xref-item-location (car defs)))
                            (target (xref-file-location-file location)))
                       (unless (equal (expand-file-name target)
                                      (expand-file-name file))
                         (error \"Hyphenated xref leaked tooling temp path: %S\"
                                target))))
                   (let ((defs (xref-backend-definitions (quote kvist) \"arr.map\")))
                     (unless (and defs (string-match-p \"src/kvist/arr/arr\\\\.kvist\" (format \"%S\" defs)))
                       (error \"Expected package xref for arr.map, got: %S\" defs)))
                   (let ((defs (xref-backend-definitions (quote kvist) \"defn\")))
                     (unless (and defs (string-match-p \"kvist form defn\" (format \"%S\" defs)))
                       (error \"Expected form xref for defn, got: %S\" defs)))
                   (let ((defs (xref-backend-definitions (quote kvist) \"fmt.println\")))
                     (unless defs
                       (error \"Expected xref definition for fmt.println\")))
                   (let ((candidates (kvist--completion-candidates)))
                     (unless (and (member \"add\" candidates)
                                  (member \"defn\" candidates)
                                  (member \"debug.break\" candidates)
                                  (member \"condition.signal\" candidates)
                                  (member \"condition.use-value!\" candidates)
                                  (member \"condition.restart-case\" candidates)
                                  (member \"condition.operation\" candidates)
                                  (member \"arr.map\" candidates)
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
                                          (cons \"C-c C-s\" (quote kvist-repl-start))
                                          (cons \"C-c C-z\" (quote kvist-repl))
                                          (cons \"C-c g g\" (quote kvist-expand-form-at-point))
                                          (cons \"C-c M-r\" (quote kvist-repl-reset))
                                          (cons \"C-c C-q\" (quote kvist-repl-stop))
                                          (cons \"C-c M-q\" (quote kvist-repl-stop))
                                          (cons \"C-c M-i\" (quote kvist-inspect-form-at-point))
                                          (cons \"C-c M-g\" (quote kvist-repl-generations))
                                          (cons \"C-c M-b\" (quote kvist-debug-native-worker))
                                          (cons \"C-c M-s\" (quote kvist-debug-breakpoint-at-point))
                                          (cons \"C-c M-e\" (quote kvist-debug-eval-form-at-point))
                                          (cons \"C-c M-c\" (quote kvist-debug-continue))
                                          (cons \"C-c M-x\" (quote kvist-debug-recover))
                                          (cons \"C-c M-n\" (quote kvist-debug-step))
                                          (cons \"C-c M-o\" (quote kvist-debug-step-over))
                                          (cons \"C-c M-u\" (quote kvist-debug-step-out))
                                          (cons \"C-c M-t\" (quote kvist-trace-form-at-point))
                                          (cons \"C-c M-f\" (quote kvist-debug-show-frame))
                                          (cons \"C-c M-p\" (quote kvist-debug-page))
                                          (cons \"C-c M-v\" (quote kvist-debug-eval-expression))
                                          (cons \"C-c M-l\" (quote kvist-debug-eval-native-form-at-point))
                                          (cons \"C-c C-w\" (quote kvist-save-form-result))
                                          (cons \"C-c C-l\" (quote kvist-cache-list))
                                          (cons \"C-c C-o\" (quote kvist-cache-open))
                                          (cons \"C-c M-d\" (quote kvist-cache-rm))
                                          (cons \"C-c a a\" (quote kvist-repl-attach))
                                          (cons \"C-c a s\" (quote kvist-repl-attached-status))
                                          (cons \"C-c a i\" (quote kvist-repl-invoke-capability))
                                          (cons \"C-c a r\" (quote kvist-repl-attached-reload))
                                          (cons \"C-c a q\" (quote kvist-repl-stop))))
                     (unless (eq (key-binding (kbd (car binding))) (cdr binding))
                       (error \"Missing binding %s\" (car binding))))
                   (with-temp-buffer
                     (setq buffer-file-name \"/tmp/kvist-completion-test.kvist\")
                     (kvist-mode)
                     (unless (and (local-variable-p (quote company-idle-delay))
                                  (null company-idle-delay))
                       (error \"Kvist did not disable idle Company completion\"))
                     (unless (eq (key-binding (kbd \"TAB\")) (quote kvist-indent-or-complete))
                       (error \"Kvist TAB does not use indent-or-complete\"))
                     (unless (eq (key-binding (kbd \"RET\")) (quote newline-and-indent))
                       (error \"Kvist RET does not insert an indented newline\"))
                     (insert \"(arr.\")
                     (let (completion-invoked)
                       (cl-letf (((symbol-function (quote kvist-complete-at-point))
                                  (lambda ()
                                    (interactive)
                                    (setq completion-invoked t))))
                         (kvist-indent-or-complete))
                       (unless completion-invoked
                         (error \"Kvist TAB did not complete a package prefix\")))
                     (let ((company-mode t)
                           company-backend)
                       (cl-letf (((symbol-function (quote kvist--company-completion-available-p))
                                  (lambda () t))
                                 ((symbol-function (quote kvist--completion-symbols))
                                  (lambda (&optional _identifier)
                                    (list (list :name \"arr.range\"
                                                :signature \"(range [& rest])\"))))
                                 ((symbol-function (quote company-begin-backend))
                                  (lambda (backend)
                                    (setq company-backend backend))))
                         (kvist-complete-at-point))
                       (unless (eq company-backend (quote kvist--company-backend))
                         (error \"Kvist did not use the active Company popup\"))
                       (unless (member \"arr.range\"
                                       (kvist--company-backend
                                        (quote candidates) \"arr.\"))
                         (error \"Kvist Company backend lost candidates\"))
                       (unless (equal (kvist--company-backend
                                       (quote annotation) \"arr.range\")
                                      \"  (range [& rest])\")
                         (error \"Kvist Company backend lost signatures\")))
                     (let ((this-command (quote indent-for-tab-command)))
                       (cl-letf (((symbol-function (quote kvist--completion-symbols))
                                  (lambda (&optional _identifier)
                                    (list (list :name \"arr.range\"
                                                :signature \"(range [& rest])\")))))
                         (let* ((capf (kvist-completion-at-point))
                                (table (nth 2 capf))
                                (candidates (all-completions \"arr.\" table))
                                (metadata (funcall table \"arr.range\" nil (quote metadata)))
                                (annotation
                                 (cdr (assq (quote annotation-function) metadata))))
                           (unless (member \"arr.range\" candidates)
                             (error \"Missing qualified CAPF candidate\"))
                           (unless (equal (funcall annotation \"arr.range\")
                                          \"  (range [& rest])\")
                             (error \"Missing CAPF signature annotation\")))))
                     (let ((this-command (quote company-complete-common))
                           (tooling-calls 0)
                           (kvist--editor-symbol-cache
                            (list :file buffer-file-name
                                  :tick (buffer-chars-modified-tick)
                                  :symbols
                                  (list (list :name \"arr.iterate\")))))
                       (cl-letf (((symbol-function (quote kvist--complete-symbols))
                                  (lambda (&optional _identifier _file)
                                    (setq tooling-calls (1+ tooling-calls))
                                    (list (list :name \"arr.range\"
                                                :signature \"(range [& rest])\")))))
                         (let* ((capf (kvist-completion-at-point))
                                (table (nth 2 capf))
                                (candidates (all-completions \"arr.\" table)))
                           (unless (and (null candidates) (= tooling-calls 0))
                             (error \"Typing qualifier invoked tooling: %S\"
                                    candidates)))
                         (let* ((kvist--manual-completion-request t)
                                (capf (kvist-completion-at-point))
                                (table (nth 2 capf))
                                (candidates (all-completions \"arr.\" table)))
                           (unless (and (member \"arr.range\" candidates)
                                        (= tooling-calls 1))
                             (error \"TAB did not fetch package symbols: %S\"
                                    candidates)))
                         (insert \"r\")
                         (let* ((this-command (quote self-insert-command))
                                (capf (kvist-completion-at-point))
                                (table (nth 2 capf))
                                (candidates (all-completions \"arr.r\" table)))
                           (unless (and (member \"arr.range\" candidates)
                                        (= tooling-calls 1))
                             (error \"Typing did not filter cached symbols: %S\"
                                    candidates))))))
                   (with-temp-buffer
                     (kvist-repl-mode)
                     (unless (member (quote kvist-completion-at-point)
                                     completion-at-point-functions)
                       (error \"Kvist REPL is missing symbol completion\"))
                     (unless (eq (key-binding (kbd \"C-c M-o\"))
                                 (quote kvist-repl-clear-buffer))
                       (error \"Kvist REPL is missing C-c M-o clear binding\"))
                     (kvist--repl-insert-prompt)
                     (insert \"(+ 1 1)\\n\")
                     (kvist--repl-insert-response
                      (list :success t :text \"2\"))
                     (let ((transcript
                            (buffer-substring-no-properties
                             (point-min) (point-max))))
                       (unless (equal
                                transcript
                                \"kvist=> (+ 1 1)\\n2\\nkvist=> \")
                         (error \"Unexpected interactive REPL transcript: %S\"
                                transcript))
                       (when (string-match-p \"=> 2\" transcript)
                         (error \"Interactive REPL result retained overlay prefix\")))
                     (insert \"(+ 40 2)\")
                     (setq kvist--repl-history (list \"(+ 1 1)\"))
                     (kvist--repl-clear-interface \"/tmp/example.kvist\")
                     (let ((cleared
                            (buffer-substring-no-properties
                             (point-min) (point-max))))
                       (when (string-match-p \"=> 2\" cleared)
                         (error \"Cleared REPL retained old transcript: %S\"
                                cleared))
                       (unless (string-suffix-p
                                \"kvist=> (+ 40 2)\" cleared)
                         (error \"Cleared REPL lost current input: %S\"
                                cleared))
                       (unless (equal kvist--repl-history
                                      (list \"(+ 1 1)\"))
                         (error \"Cleared REPL lost input history\"))))
                   (goto-char (point-min))
                   (search-forward \"(add 1\")
                   (let* ((bounds (kvist--top-level-bounds))
                          (form (buffer-substring-no-properties
                                 (car bounds) (cdr bounds))))
                     (unless (equal form \"(add 1 2)\")
                       (error
                        \"Expected direct comment child for C-c C-c, got: %S\"
                        form)))
                   (goto-char (point-min))
                   (search-forward \"(add 1\")
                   (backward-char 2)
                   (let* ((bounds (kvist--inspect-form-bounds-at-point))
                          (form (buffer-substring-no-properties
                                 (car bounds) (cdr bounds))))
                     (unless (equal form \"(add 1 2)\")
                       (error
                        \"Expected inspection on call head to select call, got: %S\"
                        form)))
                   (dolist (target (list \"dynamic\" \"[dynamic]int\"))
                     (goto-char (point-min))
                     (search-forward target)
                     (backward-char 1)
                     (let* ((bounds (kvist--inspect-form-bounds-at-point))
                            (form (buffer-substring-no-properties
                                   (car bounds) (cdr bounds))))
                       (unless (string-prefix-p
                                \"([dynamic]int [0 1 2\" form)
                         (error
                          \"Expected compound type-call head to select call, got: %S\"
                          form))))
                   (goto-char (point-min))
                   (search-forward \"map[string]int\")
                   (backward-char 1)
                   (let* ((bounds (kvist--inspect-form-bounds-at-point))
                          (form (buffer-substring-no-properties
                                 (car bounds) (cdr bounds))))
                     (unless (equal form \"(map[string]int {\\\"a\\\" 7})\")
                       (error
                        \"Expected generic type-call head to select call, got: %S\"
                        form)))
                   (goto-char (point-min))
                   (search-forward \"  (with-allocator\")
                   (beginning-of-line)
                   (skip-chars-forward \" \\t\")
                   (let* ((bounds (kvist--form-bounds-at-point))
                          (form (buffer-substring-no-properties (car bounds) (cdr bounds))))
                     (unless (string-prefix-p \"(with-allocator\" form)
                       (error \"Expected with-allocator form, got: %s\" form)))
                   (let (eval-status)
                     (cl-letf (((symbol-function (quote message))
                                (lambda (format-string &rest args)
                                  (setq eval-status
                                        (apply (quote format)
                                               format-string args)))))
                       (call-interactively (quote kvist-eval-buffer))
                       (kvist-repl-wait))
                     (unless (equal eval-status \"=> ok\")
                       (error \"Expected successful native eval-buffer status, got: %S\"
                              eval-status)))
                   (when (get-buffer kvist-generated-buffer-name)
                     (error \"Ordinary eval unexpectedly opened generated Odin\"))
                   (call-interactively (quote kvist-macroexpand-form-at-point))
                   (kvist-repl-wait)
                   (let ((macro-text (with-current-buffer kvist-macroexpand-buffer-name
                                       (buffer-substring-no-properties (point-min) (point-max)))))
                     (unless (string-match-p \"context\\\\.allocator allocator\" macro-text)
                       (error \"Expected macroexpand allocator set, got: %s\" macro-text)))
                   (goto-char (point-min))
                   (search-forward \"(add 1 2)\")
                   (call-interactively (quote kvist-expand-form-at-point))
                   (kvist-repl-wait)
                   (with-current-buffer kvist-generated-buffer-name
                     (goto-char (point-min))
                     (unless (and (search-forward \"kvist_repl_run\" nil t)
                                  (search-forward \"kvist_repl_result_value := add(1, 2)\" nil t))
                       (error \"Expected generated native REPL wrapper\")))
                   (goto-char (point-min))
                   (search-forward \"(add 1 2)\")
                   (call-interactively (quote kvist-insert-form-result))
                   (kvist-repl-wait)
                   (goto-char (point-min))
                   (unless (search-forward \";; => 3\" nil t)
                     (error \"Expected inserted eval comment\"))
                   (goto-char (point-min))
                   (search-forward \"(add 1 2)\")
                   (call-interactively (quote kvist-inspect-form-at-point))
                   (kvist-repl-wait)
                   (let ((inspect-text
                          (with-current-buffer kvist-inspect-buffer-name
                            (buffer-substring-no-properties
                             (point-min) (point-max)))))
                     (unless (and (string-match-p \"Type: int\" inspect-text)
                                  (string-match-p \"ABI: value:int\" inspect-text)
                                  (string-match-p \"Shape: scalar\" inspect-text)
                                  (string-match-p \"3\" inspect-text))
                       (error \"Expected typed live inspection, got: %s\"
                              inspect-text)))
                   (goto-char (point-min))
                   (search-forward \"(Pair {left: 1 right: \\\"two\\\"})\")
                   (call-interactively (quote kvist-inspect-form-at-point))
                   (kvist-repl-wait)
                   (let ((inspect-text
                          (with-current-buffer kvist-inspect-buffer-name
                            (buffer-substring-no-properties
                             (point-min) (point-max)))))
                     (unless
                         (and (string-match-p \"Type: Pair\" inspect-text)
                              (string-match-p \"Shape: struct\" inspect-text)
                              (string-match-p \"left: int\" inspect-text)
                              (string-match-p \"right: string\" inspect-text))
                       (error \"Expected structured inspection, got: %s\"
                              inspect-text)))
                   (with-current-buffer kvist-inspect-buffer-name
                     (unless (equal kvist--inspection-handle \"inspection-2\")
                       (error \"Expected retained structured inspection handle\"))
                     (kvist-inspect-member \"left\"))
                   (kvist-repl-wait)
                   (let ((child-text
                          (with-current-buffer kvist-inspect-buffer-name
                            (buffer-substring-no-properties
                             (point-min) (point-max)))))
                     (unless
                         (and (string-match-p
                               \"Expression: inspection-2 / left\"
                               child-text)
                              (string-match-p \"Type: int\" child-text)
                              (string-match-p \"Shape: scalar\" child-text)
                              (string-match-p \"^1$\" child-text))
                       (error \"Expected retained field inspection, got: %s\"
                              child-text)))
                   (with-current-buffer kvist-inspect-buffer-name
                     (unless
                         (string-match-p
                          \"b          return to previous inspection\"
                          (buffer-string))
                       (error \"Expected discoverable inspector back navigation\"))
                     (kvist-inspect-back)
                     (unless
                         (and (equal kvist--inspection-handle \"inspection-2\")
                              (equal kvist--inspection-shape \"struct\")
                              (string-match-p
                               \"RET/click  inspect field at point\"
                               (buffer-string)))
                       (error \"Expected inspector back to restore struct view\")))
                   (goto-char (point-min))
                   (search-forward \"([dynamic]int [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21])\")
                   (call-interactively (quote kvist-inspect-form-at-point))
                   (kvist-repl-wait)
                   (with-current-buffer kvist-inspect-buffer-name
                     (unless (equal kvist--inspection-shape \"dynamic-array\")
                       (error \"Expected navigable dynamic-array inspection\"))
                     (unless (and (= kvist--inspection-total 22)
                                  (= kvist--inspection-offset 0))
                       (error \"Expected first bounded collection page\"))
                     (kvist-inspect-next-page))
                   (kvist-repl-wait)
                   (with-current-buffer kvist-inspect-buffer-name
                     (unless (and (= kvist--inspection-offset 20)
                                  (save-excursion
                                    (goto-char (point-min))
                                    (search-forward \"[20] 20\" nil t)))
                       (error \"Expected second bounded collection page\"))
                     (kvist-inspect-index 1))
                   (kvist-repl-wait)
                   (let ((child-text
                          (with-current-buffer kvist-inspect-buffer-name
                            (buffer-substring-no-properties
                             (point-min) (point-max)))))
                     (unless
                         (and (string-match-p \"/ \\\\[1\\\\]\" child-text)
                              (string-match-p \"Type: int\" child-text)
                              (string-match-p \"^1$\" child-text))
                       (error \"Expected retained index inspection, got: %s\"
                              child-text)))
                   (goto-char (point-min))
                   (search-forward \"(map[string]int {\\\"a\\\" 7})\")
                   (call-interactively (quote kvist-inspect-form-at-point))
                   (kvist-repl-wait)
                   (with-current-buffer kvist-inspect-buffer-name
                     (unless (equal kvist--inspection-shape \"map\")
                       (error \"Expected navigable map inspection\"))
                     (kvist-inspect-map-key \"\\\"a\\\"\"))
                   (kvist-repl-wait)
                   (let ((child-text
                          (with-current-buffer kvist-inspect-buffer-name
                            (buffer-substring-no-properties
                             (point-min) (point-max)))))
                     (unless
                         (and (string-match-p \"/ \\\\[\\\"a\\\"\\\\]\" child-text)
                              (string-match-p \"Type: int\" child-text)
                              (string-match-p \"^7$\" child-text))
                       (error \"Expected retained map entry inspection, got: %s\"
                              child-text)))
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
                     (unless (= (line-number-at-pos) 7)
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
                   (search-forward \"(announce)\")
                   (call-interactively (quote kvist-insert-form-result))
                   (kvist-repl-wait)
                   (goto-char (point-min))
                   (unless (search-forward \";; => announced\" nil t)
                     (error \"Expected inserted void-call eval comment\"))
                   (kvist-repl-generations)
                   (kvist-repl-wait)
                   (with-current-buffer kvist-generations-buffer-name
                     (let ((generation-text
                            (buffer-substring-no-properties
                             (point-min) (point-max))))
                       (unless
                           (and (string-match-p
                                 \"Loaded native generations: [1-9]\"
                                 generation-text)
                                (string-match-p \"generation_[0-9]+\\\\.odin\"
                                                generation-text)
                                (string-match-p \"generation_[0-9]+\\\\.map\"
                                                generation-text))
                         (error \"Expected live generation inventory, got: %s\"
                                generation-text))))
                   (setq kvist-test-debug-session nil)
                   (let ((kvist-native-debugger-launch-function
                          (lambda (metadata)
                            (setq kvist-test-debug-session metadata))))
                     (kvist-debug-native-worker)
                     (kvist-repl-wait))
                   (let ((debug-session kvist-test-debug-session))
                     (unless
                         (and (numberp (plist-get debug-session :worker-pid))
                              (> (plist-get debug-session :worker-pid) 0)
                              (= (plist-get debug-session :worker-epoch) 1)
                              (member \"native-attach\"
                                      (plist-get debug-session :capabilities)))
                       (error \"Expected native debug-session metadata, got: %s\"
                              debug-session)))
                   (setq kvist-test-breakpoints nil)
                   (let ((kvist-native-breakpoint-function
                          (lambda (locations)
                            (setq kvist-test-breakpoints locations))))
                     (goto-char (point-min))
                     (search-forward \"(defn add \")
                     (beginning-of-line)
                     (kvist-debug-breakpoint-at-point)
                     (kvist-repl-wait))
                   (unless
                       (and kvist-test-breakpoints
                            (stringp
                             (alist-get
                              (quote generated_path)
                              (car kvist-test-breakpoints)))
                            (numberp
                             (alist-get
                              (quote generated_start_line)
                              (car kvist-test-breakpoints))))
                     (error \"Expected translated Kvist breakpoints, got: %s\"
                            kvist-test-breakpoints))
                   (goto-char (point-min))
                   (search-forward \"(add 1 2)\")
                   (kvist-debug-eval-form-at-point)
                   (kvist-debug-wait-for-pause)
                   (let ((session (kvist--repl-session)))
                     (unless
                         (and (stringp
                               (kvist--repl-session-pause-id session))
                              (overlayp
                               (kvist--repl-session-pause-overlay session))
                              (alist-get
                               (quote frame_id)
                               (kvist--repl-session-debug-frame session)))
                       (error \"Expected visible instrumented Kvist pause\"))
                     (with-current-buffer kvist-test-source-buffer
                       (unless kvist-debug-source-mode
                         (error \"Expected source-buffer debug controls\"))
                       (let* ((overlay
                               (kvist--repl-session-pause-overlay session))
                              (prompt (overlay-get overlay (quote after-string)))
                              (frame
                               (kvist--repl-session-debug-frame session)))
                         (unless
                             (and (string-match-p \"next\" prompt)
                                  (string-match-p \"continue\" prompt)
                                  (string-match-p \"frame\" prompt)
                                  (string-match-p \"quit\" prompt)
                                  (not (string-match-p \"Kvist paused\" prompt)))
                           (error \"Unexpected source debug prompt: %S\" prompt))
                         (unless
                             (and (= (line-number-at-pos)
                                     (alist-get (quote line) frame))
                                  (= (1+ (current-column))
                                     (alist-get (quote column) frame)))
                           (error \"Point did not move to the paused source span\")))
                       (dolist
                           (binding
                            (list (cons \"n\" (quote kvist-debug-step))
                                  (cons \"o\" (quote kvist-debug-step-over))
                                  (cons \"u\" (quote kvist-debug-step-out))
                                  (cons \"c\" (quote kvist-debug-continue))
                                  (cons \"e\" (quote kvist-debug-eval-expression))
                                  (cons \"f\" (quote kvist-debug-show-frame))
                                  (cons \"p\" (quote kvist-debug-page))
                                  (cons \"q\" (quote kvist-debug-abort))))
                         (unless (eq (key-binding (kbd (car binding)))
                                     (cdr binding))
                           (error \"Missing source debug key %s\"
                                  (car binding)))))
                     (kvist-debug-show-frame)
                     (let ((deadline (+ (float-time) 30.0)))
                       (while
                           (and (not (get-buffer
                                      kvist-debug-frame-buffer-name))
                                (< (float-time) deadline))
                         (accept-process-output
                          (kvist--repl-session-process session)
                          0.1)))
                       (unless (get-buffer kvist-debug-frame-buffer-name)
                         (error \"Expected queried Kvist debug frame\")))
                     (with-current-buffer kvist-debug-frame-buffer-name
                       (let ((frame-text
                              (buffer-substring-no-properties
                               (point-min) (point-max))))
                         (unless
                             (and (string-match-p \"Commands: n next/into\"
                                                  frame-text)
                                  (string-match-p \"Phase: before-eval\"
                                                  frame-text)
                                  (string-match-p
                                   \"Locals: none exposed\"
                                   frame-text))
                           (error \"Unexpected Kvist frame: %s\"
                                  frame-text)))
                       (dolist
                           (binding
                            (list (cons \"n\" (quote kvist-debug-step))
                                  (cons \"o\" (quote kvist-debug-step-over))
                                  (cons \"u\" (quote kvist-debug-step-out))
                                  (cons \"c\" (quote kvist-debug-continue))
                                  (cons \"e\" (quote kvist-debug-eval-expression))
                                  (cons \"p\" (quote kvist-debug-page))
                                  (cons \"g\" (quote kvist-debug-show-frame))
                                  (cons \"q\" (quote kvist-debug-abort))))
                         (unless (eq (key-binding (kbd (car binding)))
                                     (cdr binding))
                           (error \"Missing debug-frame key %s\"
                                  (car binding)))))
                     (kvist--present-debug-value
                      \"x\"
                      (list :success t :type \"int\" :text \"5\"))
                     (with-current-buffer kvist-debug-value-buffer-name
                       (let ((value-text
                              (buffer-substring-no-properties
                               (point-min) (point-max))))
                         (unless (string= value-text \"x: int\\n\\n5\")
                           (error \"Unexpected Kvist debug value: %s\"
                                  value-text))))
                     (kvist--present-debug-page
                      (list :success t
                            :shape \"dynamic-array\"
                            :element-type \"int\"
                            :offset 1
                            :limit 2
                            :total 4
                            :entries
                            (list
                             (list (cons (quote index) 1)
                                   (cons (quote value) \"20\"))
                             (list (cons (quote index) 2)
                                   (cons (quote value) \"30\")))
                            :collections
                            (list
                             (list
                              (cons (quote path) \"values[2].children\")
                              (cons (quote shape) \"dynamic-array\"))))
                      \"values\"
                      file
                      (current-buffer)
                      \"pause-test\")
                     (with-current-buffer kvist-debug-page-buffer-name
                       (let ((page-text
                              (buffer-substring-no-properties
                               (point-min) (point-max))))
                         (unless
                             (and
                              (string-match-p
                               \"Paused collection: values\"
                               page-text)
                              (string-match-p \"\\\\[1\\\\]  20\" page-text)
                              (string-match-p \"Page: 2-3 of 4\" page-text)
                              (string-match-p
                               \"Discovered collections\"
                               page-text)
                              (string-match-p
                               \"values\\\\[2\\\\]\\\\.children\"
                               page-text)
                              (eq (key-binding (kbd \"n\"))
                                  (quote kvist-debug-page-next))
                              (eq (key-binding (kbd \"p\"))
                                  (quote kvist-debug-page-previous))
                              (eq (key-binding (kbd \"g\"))
                                  (quote kvist-debug-page-refresh)))
                           (error \"Unexpected Kvist debug page: %s\"
                                  page-text))))
                     (let* ((session
                             (with-current-buffer kvist-test-source-buffer
                               (kvist--repl-session)))
                            (pending
                             (kvist--repl-session-pending session))
                            (outer-count (hash-table-count pending))
                            (deadline (+ (float-time) 30.0)))
                       (with-current-buffer kvist-test-source-buffer
                         (goto-char (point-min))
                         (search-forward \"(add 1 2)\")
                         (kvist-debug-eval-native-form-at-point))
                       (while
                           (and (> (hash-table-count pending) outer-count)
                                (< (float-time) deadline))
                         (accept-process-output
                          (kvist--repl-session-process session)
                          0.1))
                       (when (> (hash-table-count pending) outer-count)
                         (error
                          \"Timed out waiting for native break evaluation\")))
                     (unless
                         (and
                          (kvist--repl-session-pause-id
                           (with-current-buffer kvist-test-source-buffer
                             (kvist--repl-session)))
                          (with-current-buffer kvist-result-buffer-name
                            (string-match-p \"3\" (buffer-string))))
                       (error
                        \"Expected native break evaluation to preserve the outer pause\"))
                     (kvist-debug-continue)
                     (kvist-repl-wait)
                     (when (kvist--repl-session-pause-id
                            (kvist--repl-session))
                       (error \"Expected Kvist pause to clear after continue\"))
                     (kvist--repl-request
                      \"eval\"
                      \"(defn condition-value [x: int] -> int (do (condition.signal \\\"inspect x\\\") (+ x 1)))\"
                      (lambda (result)
                        (unless (plist-get result :success)
                          (error \"Could not define condition-value: %s\"
                                 (plist-get result :message))))
                      nil file)
                     (kvist-repl-wait)
                     (kvist--repl-request
                      \"eval\"
                      \"(condition-value 5)\"
                      (lambda (result)
                        (unless
                            (and (plist-get result :success)
                                 (string-match-p \"6\"
                                                 (plist-get result :text)))
                          (error \"Unexpected condition result: %S\" result)))
                      nil file)
                     (kvist-debug-wait-for-pause)
                     (let* ((condition-session (kvist--repl-session))
                            (condition-event
                             (kvist--repl-session-condition
                              condition-session)))
                       (unless
                           (and condition-event
                                (equal
                                 (alist-get (quote condition_type)
                                            condition-event)
                                 \"kvist/condition\")
                                (equal (alist-get (quote message)
                                                  condition-event)
                                       \"inspect x\")
                                (get-buffer kvist-condition-buffer-name))
                         (error \"Expected visible Kvist condition\"))
                       (with-current-buffer kvist-condition-buffer-name
                         (let ((condition-text
                                (buffer-substring-no-properties
                                 (point-min) (point-max))))
                           (unless
                               (and
                                (string-match-p
                                 \"Condition: kvist/condition\"
                                 condition-text)
                                (string-match-p \"Message: inspect x\"
                                                condition-text)
                                (string-match-p \"x: int = 5\"
                                                condition-text)
                                (string-match-p \"continue\"
                                                condition-text)
                                (eq (key-binding (kbd \"r\"))
                                    (quote
                                     kvist-debug-recover)))
                             (error \"Unexpected Kvist condition: %s\"
                                    condition-text))))
                       (kvist-debug-recover \"continue\")
                       (kvist-repl-wait)
                       (when
                           (kvist--repl-session-pause-id
                            condition-session)
                         (error
                          \"Expected Kvist condition to clear after restart\")))
                     (kvist--repl-request
                      \"eval\"
                      \"(defn repair-value [x: int] -> int (do (defvar value: int x) (condition.use-value! value \\\"replace value\\\") value))\"
                      (lambda (result)
                        (unless (plist-get result :success)
                          (error \"Could not define repair-value: %s\"
                                 (plist-get result :message))))
                      nil file)
                     (kvist-repl-wait)
                     (kvist--repl-request
                      \"eval\"
                      \"(repair-value 5)\"
                      (lambda (result)
                        (unless
                            (and (plist-get result :success)
                                 (string-match-p \"42\"
                                                 (plist-get result :text)))
                          (error \"Unexpected use-value result: %S\"
                                 result)))
                      nil file)
                     (kvist-debug-wait-for-pause)
                     (with-current-buffer kvist-condition-buffer-name
                       (let ((condition-text
                              (buffer-substring-no-properties
                               (point-min) (point-max))))
                         (unless
                             (and
                              (string-match-p \"use-value\"
                                              condition-text)
                              (string-match-p \"value: int\"
                                              condition-text)
                              (string-match-p \"value: int = 5\"
                                              condition-text))
                           (error \"Unexpected use-value condition: %s\"
                                  condition-text))))
                     (kvist-debug-recover \"use-value\" \"42\")
                     (kvist-repl-wait)
                     (when
                         (kvist--repl-session-pause-id
                          (kvist--repl-session))
                       (error
                        \"Expected use-value condition to clear after restart\"))
                     (kvist--repl-request
                      \"eval\"
                      \"(defn repair-string [x: string] -> string (do (defvar value: string x) (condition.use-value! value \\\"replace string\\\") value))\"
                      (lambda (result)
                        (unless (plist-get result :success)
                          (error \"Could not define repair-string: %s\"
                                 (plist-get result :message))))
                      nil file)
                     (kvist-repl-wait)
                     (kvist--repl-request
                      \"eval\"
                      \"(repair-string \\\"old\\\")\"
                      (lambda (result)
                        (unless
                            (and (plist-get result :success)
                                 (string-match-p \"hello emacs\"
                                                 (plist-get result :text)))
                          (error \"Unexpected string restart result: %S\"
                                 result)))
                      nil file)
                     (kvist-debug-wait-for-pause)
                     (with-current-buffer kvist-condition-buffer-name
                       (let ((condition-text
                              (buffer-substring-no-properties
                               (point-min) (point-max))))
                         (unless
                             (and
                              (string-match-p \"use-value\"
                                              condition-text)
                              (string-match-p \"value: string\"
                                              condition-text))
                           (error \"Unexpected string condition: %s\"
                                  condition-text))))
                     (kvist-debug-recover
                      \"use-value\" \"hello emacs\")
                     (kvist-repl-wait)
                     (kvist--repl-request
                      \"eval\"
                      \"(defn retry-region [] -> int (do (defvar attempts: int 0) (condition.restart-case (do (inc! attempts) (condition.signal \\\"retry region\\\") (inc! attempts))) attempts))\"
                      (lambda (result)
                        (unless (plist-get result :success)
                          (error \"Could not define retry-region: %s\"
                                 (plist-get result :message))))
                      nil file)
                     (kvist-repl-wait)
                     (kvist--repl-request
                      \"eval\"
                      \"(retry-region)\"
                      (lambda (result)
                        (unless
                            (and (plist-get result :success)
                                 (string-match-p \"2\"
                                                 (plist-get result :text)))
                          (error \"Unexpected retry-region result: %S\"
                                 result)))
                      nil file)
                     (kvist-debug-wait-for-pause)
                     (with-current-buffer kvist-condition-buffer-name
                       (let ((condition-text
                              (buffer-substring-no-properties
                               (point-min) (point-max))))
                         (unless
                             (and
                              (string-match-p \"retry\"
                                              condition-text)
                              (string-match-p \"skip\"
                                              condition-text))
                           (error
                            \"Unexpected restart-case condition: %s\"
                            condition-text))))
                     (let* ((restart-session (kvist--repl-session))
                            (previous-condition
                             (kvist--repl-session-condition
                              restart-session))
                            (deadline (+ (float-time) 30.0)))
                       (kvist-debug-recover \"retry\")
                       (while
                           (and
                            (let ((current-condition
                                   (kvist--repl-session-condition
                                    restart-session)))
                              (or (null current-condition)
                                  (eq current-condition
                                      previous-condition)))
                            (< (float-time) deadline))
                         (accept-process-output
                          (kvist--repl-session-process restart-session)
                          0.1))
                       (unless
                           (kvist--repl-session-condition
                            restart-session)
                         (error
                          \"Expected retry to reach the condition again\"))
                       (kvist-debug-recover \"skip\"))
                     (kvist-repl-wait)
                     (when
                         (kvist--repl-session-pause-id
                          (kvist--repl-session))
                       (error
                        \"Expected restart-case condition to clear after skip\"))
                     (kvist--repl-request
                      \"eval\"
                      \"(defn paused-values [values: [dynamic]int] -> int (do (debug.break) values[0]))\"
                      (lambda (result)
                        (unless (plist-get result :success)
                          (error \"Could not define paused-values: %s\"
                                 (plist-get result :message))))
                      nil file)
                     (kvist-repl-wait)
                     (kvist--repl-request
                      \"eval\"
                      \"(paused-values ([dynamic]int [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21]))\"
                      (lambda (result)
                        (unless (plist-get result :success)
                          (error \"Could not call paused-values: %s\"
                                 (plist-get result :message))))
                      nil file)
                     (kvist-debug-wait-for-pause)
                     (let* ((session (kvist--repl-session))
                            (live-pause
                             (kvist--repl-session-pause-id session)))
                       (kvist-debug-page \"values\")
                       (let ((deadline (+ (float-time) 30.0)))
                         (while
                             (and
                              (not
                               (and
                                (get-buffer kvist-debug-page-buffer-name)
                                (with-current-buffer
                                    kvist-debug-page-buffer-name
                                  (and
                                   (equal kvist--debug-page-pause-id
                                          live-pause)
                                   (= (or kvist--debug-page-offset -1)
                                      0)))))
                              (< (float-time) deadline))
                           (accept-process-output
                            (with-current-buffer kvist-test-source-buffer
                              (kvist--repl-session-process
                               (kvist--repl-session)))
                            0.1)))
                         (with-current-buffer kvist-debug-page-buffer-name
                           (unless
                               (and
                                (equal kvist--debug-page-path \"values\")
                                (= kvist--debug-page-total 22)
                                (string-match-p
                                 \"\\\\[19\\\\]  19\"
                                 (buffer-string)))
                             (error
                              \"Expected first live Kvist collection page: %s\"
                              (buffer-string)))
                           (kvist-debug-page-next)))
                       (let ((deadline (+ (float-time) 30.0)))
                         (while
                             (and
                              (not
                               (with-current-buffer
                                   kvist-debug-page-buffer-name
                                 (= (or kvist--debug-page-offset -1)
                                    20)))
                              (< (float-time) deadline))
                           (accept-process-output
                            (with-current-buffer kvist-test-source-buffer
                              (kvist--repl-session-process
                               (kvist--repl-session)))
                            0.1)))
                         (with-current-buffer kvist-debug-page-buffer-name
                           (unless
                               (and
                                (= kvist--debug-page-offset 20)
                                (string-match-p
                                 \"\\\\[20\\\\]  20\"
                                 (buffer-string))
                                (string-match-p
                                 \"Page: 21-22 of 22\"
                                 (buffer-string)))
                             (error
                              \"Expected second live Kvist collection page: %s\"
                              (buffer-string)))))
                       (let* ((session (kvist--repl-session))
                              (previous-pause
                               (kvist--repl-session-pause-id session))
                              (deadline (+ (float-time) 30.0)))
                         (kvist-debug-step)
                         (while
                             (and
                              (or
                               (null
                                (kvist--repl-session-pause-id session))
                               (equal
                                (kvist--repl-session-pause-id session)
                                previous-pause))
                              (< (float-time) deadline))
                           (accept-process-output
                            (kvist--repl-session-process session)
                            0.1))
                         (unless
                             (and
                              (kvist--repl-session-pause-id session)
                              (not
                               (equal
                                (kvist--repl-session-pause-id session)
                                previous-pause)))
                           (error
                            \"Expected Kvist step to reach a new pause\"))
                         (let ((frame-id
                                (alist-get
                                 (quote frame_id)
                                 (kvist--repl-session-debug-frame session))))
                           (unless
                               (and frame-id
                                    (with-current-buffer
                                        kvist-debug-frame-buffer-name
                                      (string-match-p
                                       (regexp-quote
                                        (format \"Frame: %s\" frame-id))
                                       (buffer-string))))
                             (error
                              \"Debug frame did not refresh after stepping\")))
                         (kvist-debug-step-out)
                         (kvist-repl-wait))
                       (kvist--repl-request
                        \"eval\"
                        \"(defn traced-values [x: int] -> int (do (discard (+ x 1)) (+ x 2)))\"
                        (lambda (result)
                          (unless (plist-get result :success)
                            (error \"Could not define traced-values: %s\"
                                   (plist-get result :message))))
                        nil file)
                       (kvist-repl-wait)
                       (kvist--repl-request
                        \"eval\"
                        \"(traced-values 5)\"
                        (lambda (result)
                          (unless (plist-get result :success)
                            (error \"Could not trace traced-values: %s\"
                                   (plist-get result :message)))
                          (unless
                              (and (= (length (plist-get result :traces)) 2)
                                   (plist-get result :trace-truncated))
                            (error \"Unexpected Kvist trace result: %S\"
                                   result))
                          (kvist--present-trace
                           (plist-get result :traces)
                           (plist-get result :trace-truncated)
                           (plist-get result :trace-summary)
                           (plist-get result :trace-values)
                           (plist-get result :trace-values-truncated)))
                        nil file nil nil nil nil nil nil nil nil nil nil
                        t 2 t 1)
                       (kvist-repl-wait)
                       (with-current-buffer kvist-trace-buffer-name
                         (unless
                             (and
                              (string-match-p
                               \"Kvist execution trace: 2 safe points\"
                               (buffer-string))
                              (string-match-p
                               \"Δ[0-9.]+ ms\"
                               (buffer-string))
                              (string-match-p
                               \"Hotspots (time after each safe point)\"
                               (buffer-string))
                              (string-match-p
                               \"Native evaluation: [0-9.]+ ms total\"
                               (buffer-string))
                              (string-match-p \"depth 1\" (buffer-string))
                              (string-match-p
                               \"x: int  borrowed = 5\"
                               (buffer-string))
                              (string-match-p
                               \"Trace value limit reached\"
                               (buffer-string))
                              (string-match-p
                               \"Trace limit reached\"
                               (buffer-string)))
                           (error \"Unexpected Kvist trace buffer: %s\"
                                  (buffer-string)))))))
               (ignore-errors (kvist-repl-stop))
               (ignore-errors
                 (when (buffer-live-p kvist-test-source-buffer)
                   (kill-buffer kvist-test-source-buffer)))
               (ignore-errors (kill-buffer (current-buffer)))
               (delete-file file))))"

    printf 'tooling: emacs attached protocol events\n'
    emacs -Q --batch --eval \
        '(progn
           (defvar clojure-mode-map (make-sparse-keymap))
           (define-derived-mode clojure-mode prog-mode "Clojure")
           (defun clojure--put-indentation-spec (&rest _args) nil)
           (provide (quote clojure-mode))
           (add-to-list (quote load-path) "emacs")
           (require (quote kvist-eval))
           (let* ((process (start-process "kvist-attached-event-test" nil "cat"))
                  (session
                   (kvist--make-repl-session
                    :key "attached-test"
                    :process process
                    :pending (make-hash-table :test (quote equal))
                    :attached t
                    :endpoint "/tmp/kvist-attached-test"))
                  result)
             (unwind-protect
                 (progn
                   (process-put process (intern "kvist-request-reload")
                                (list :text ""))
                   (puthash "reload"
                            (lambda (value) (setq result value))
                            (kvist--repl-session-pending session))
                   (kvist--repl-handle-event
                    session
                    (quote ((id . "reload")
                            (kind . "reload-requested")
                            (success . t)
                            (generation . 7)
                            (reload_requested . t))))
                   (kvist--repl-handle-event
                    session
                    (quote ((id . "reload")
                            (kind . "reload-complete")
                            (success . t)
                            (generation . 8)
                            (attached_capabilities
                             . (((name . "app/echo")
                                 (signature . "proc(string)->string")))))))
                   (kvist--repl-handle-event
                    session
                    (quote ((id . "reload")
                            (kind . "complete")
                            (success . t)
                            (generation . 8))))
                   (unless (and (plist-get result :success)
                                (plist-get result :reload-requested)
                                (= (plist-get result :generation) 8)
                                (equal
                                 (alist-get
                                  (quote name)
                                  (car
                                   (plist-get
                                    result
                                    :attached-capabilities)))
                                 "app/echo"))
                     (error "Unexpected attached result: %S" result)))
               (when (process-live-p process)
                 (delete-process process)))))'
else
    printf 'tooling: emacs not found, skipping byte compile\n'
fi

printf 'tooling integration ok\n'
