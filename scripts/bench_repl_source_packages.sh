#!/usr/bin/env sh
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

requests="$tmp_dir/requests.jsonl"
events="$tmp_dir/events.jsonl"
context_path=${KVIST_BENCH_CONTEXT:-"$ROOT/benchmarks/repl_native_packages.kvist"}

if [ "${KVIST_BENCH_COMPILER:-}" ]; then
    compiler=$KVIST_BENCH_COMPILER
else
    compiler="$tmp_dir/kvist"
    odin build "$ROOT/src/cli/kvist" -o:speed -out:"$compiler"
fi

cat >"$requests" <<'JSONL'
{"id":"establish-context","op":"eval","source":"42"}
{"id":"load-data","op":"eval","source":"(import data \"kvist:data\")\n(defn profile-card [name: string, role: string] -> Data\n  [:article {:class \"profile\"}\n   [:h2 name]\n   [:p role]])","source_path":"/virtual/repl-native-packages.kvist","line":1,"column":1,"no_print":true,"defer_debug_values":true}
{"id":"post-import-add","op":"eval","source":"(+ 20 22)"}
{"id":"post-import-history","op":"eval","source":"(+ *1 1)"}
{"id":"define-scalar-macro","op":"eval","source":"(defmacro session-add [x] (quasiquote (+ (unquote x) 2)))","no_print":true,"defer_debug_values":true}
{"id":"expanded-macro-call","op":"eval","source":"(session-add 40)"}
{"id":"typed-scalar-let","op":"eval","source":"(let [x: f64 20] (+ x 22.0))"}
{"id":"mixed-scalar-number","op":"eval","source":"(+ 20 22.0)"}
{"id":"define-scalar-helper","op":"eval","source":"(defn session-inc [x: int] -> int (+ x 1))\n(defn session-sequenced [x: int] -> int (discard (+ x 100)) (+ x 2))\n(defn session-mutable [x: int] -> int (defvar total: int x) (set! total (+ total 2)) total)\n(defn session-early-return [x: int] -> int (if (< x 0) (return 40)) (+ x 2))\n(defn session-return-inner [x: int] -> int (if (< x 0) (return 5)) (+ x 1))\n(defn session-return-outer [x: int] -> int (+ (session-return-inner x) 10))\n(defn session-branch-mutable [x: int] -> int (defvar total: int 0) (if (< x 0) (set! total 40) (set! total x)) total)\n(defn session-grouped-branch [x: int] -> int (defvar total: int 0) (if (< x 0) (do (set! total 20) (if true (set! total (+ total 20)))) (set! total x)) total)\n(defn session-loop-count [limit: int] -> int (defvar index: int 0) (while (< index limit) (set! index (+ index 1))) index)\n(defn session-loop-sum [limit: int] -> int (defvar index: int 0) (defvar total: int 0) (while (< index limit) (set! total (+ total index)) (set! index (+ index 1))) total)\n(defn session-loop-find [limit: int needle: int] -> int (defvar index: int 0) (while (< index limit) (if (= index needle) (return index)) (set! index (+ index 1))) -1)\n(defn session-loop-inc [limit: int] -> int (defvar index: int 0) (while (< index limit) (inc! index)) index)\n(defn session-loop-continue [limit: int divisor: int] -> int (defvar index: int 0) (defvar total: int 0) (while (< index limit) (inc! index) (when (= (% index divisor) 0) (continue)) (set! total (+ total index))) total)\n(defn session-loop-break [stop: int] -> int (defvar index: int 0) (while true (when (= index stop) (break)) (inc! index)) index)\n(defn session-loop-nested-break [outer-limit: int inner-limit: int] -> int (defvar outer: int 0) (defvar total: int 0) (while (< outer outer-limit) (defvar inner: int 0) (while true (when (= inner inner-limit) (break)) (inc! total) (inc! inner)) (inc! outer)) total)\n(defn session-valid-match? [match: string] -> bool (or (= match \"focus\") (= match \"act\") (= match \"open\")))","no_print":true,"defer_debug_values":true}
{"id":"direct-scalar-helper","op":"eval","source":"(session-inc 41)"}
{"id":"composed-scalar-helper","op":"eval","source":"(+ (session-inc (+ 19 1)) 21)"}
{"id":"composed-scalar-helper-repeat","op":"eval","source":"(+ (session-inc (+ 19 1)) 21)"}
{"id":"scalar-do-sequence","op":"eval","source":"(do (discard (+ 20 22)) 42)"}
{"id":"composed-sequenced-helper","op":"eval","source":"(+ (session-sequenced (+ 19 1)) 20)"}
{"id":"scalar-mutable-block","op":"eval","source":"(do (defvar value: int 20) (set! value (+ value 22)) value)"}
{"id":"composed-mutable-helper","op":"eval","source":"(+ (session-mutable (+ 19 1)) 20)"}
{"id":"early-return-taken","op":"eval","source":"(+ (session-early-return -1) 2)"}
{"id":"early-return-fallthrough","op":"eval","source":"(+ (session-early-return 40) 0)"}
{"id":"nested-early-return","op":"eval","source":"(+ (session-return-outer -1) 27)"}
{"id":"branch-mutation-taken","op":"eval","source":"(+ (session-branch-mutable -1) 2)"}
{"id":"branch-mutation-fallthrough","op":"eval","source":"(+ (session-branch-mutable 40) 2)"}
{"id":"grouped-branch-mutation","op":"eval","source":"(+ (session-grouped-branch -1) 2)"}
{"id":"scalar-while-block","op":"eval","source":"(do (defvar value: int 0) (while (< value 42) (set! value (+ value 1))) value)"}
{"id":"scalar-while-count","op":"eval","source":"(+ (session-loop-count (+ 39 1)) 2)"}
{"id":"scalar-while-sum","op":"eval","source":"(* (session-loop-sum (+ 5 2)) 2)"}
{"id":"scalar-while-return","op":"eval","source":"(+ (session-loop-find 100 (+ 39 1)) 2)"}
{"id":"scalar-while-inc-10k","op":"eval","source":"(+ (session-loop-inc (+ 9999 1)) 0)"}
{"id":"scalar-while-continue-10k","op":"eval","source":"(+ (session-loop-continue (+ 9999 1) 2) 0)"}
{"id":"scalar-while-break-10k","op":"eval","source":"(+ (session-loop-break (+ 9999 1)) 0)"}
{"id":"scalar-while-nested-break-10k","op":"eval","source":"(+ (session-loop-nested-break (+ 99 1) 100) 0)"}
{"id":"string-equality","op":"eval","source":"(= \"Kvist\" \"Kvist\")"}
{"id":"composed-string-helper","op":"eval","source":"(if (session-valid-match? \"focus\") 42 0)"}
{"id":"load-str","op":"eval","source":"(import str \"kvist:str\")","no_print":true,"defer_debug_values":true}
{"id":"string-predicate-first","op":"eval","source":"(str.contains? \"Kvist REPL\" \"REPL\")"}
{"id":"string-predicate-direct","op":"eval","source":"(str.contains? \"Kvist REPL\" \"REPL\")"}
{"id":"string-predicate-composed","op":"eval","source":"(and (str.contains? \"Kvist REPL\" \"REPL\") true)"}
{"id":"string-predicate-composed-repeat","op":"eval","source":"(and (str.contains? \"Kvist REPL\" \"REPL\") true)"}
{"id":"borrowed-string-result-first","op":"eval","source":"(str.trim \" Kvist \")"}
{"id":"borrowed-string-result-composed","op":"eval","source":"(= (str.trim \" Kvist \") \"Kvist\")"}
{"id":"owned-string-result-first","op":"eval","source":"(str.lower \"KVIST\")"}
{"id":"owned-string-result-composed","op":"eval","source":"(= (str.lower \"KVIST\") \"kvist\")"}
{"id":"owned-borrowed-string-result-composed","op":"eval","source":"(= (str.trim (str.lower \" KVIST \")) \"kvist\")"}
{"id":"data-empty-first","op":"eval","source":"(data.empty-map)"}
{"id":"data-empty-repeat","op":"eval","source":"(data.empty-map)"}
{"id":"data-count-first","op":"eval","source":"(data.count *1)"}
{"id":"data-owned-result-composed","op":"eval","source":"(data.count (data.empty-map))"}
{"id":"data-owned-result-composed-repeat","op":"eval","source":"(data.count (data.empty-map))"}
{"id":"data-borrowed-result-first","op":"eval","source":"(data.count (data.tagged-value (data.tagged \"x\" (data.empty-map))))"}
{"id":"data-borrowed-result-composed","op":"eval","source":"(data.count (data.tagged-value (data.tagged \"x\" (data.empty-map))))"}
{"id":"profile-direct","op":"eval","source":"(profile-card \"Ada Lovelace\" \"Mathematician\")"}
{"id":"data-get-1","op":"eval","source":"(get (profile-card \"Ada Lovelace\" \"Mathematician\") 0)"}
{"id":"data-first","op":"eval","source":"(data.first (profile-card \"Ada Lovelace\" \"Mathematician\"))"}
{"id":"data-first-repeat","op":"eval","source":"(data.first (profile-card \"Ada Lovelace\" \"Mathematician\"))"}
{"id":"data-first-cache","op":"eval","source":"(data.first (profile-card \"Ada Lovelace\" \"Mathematician\"))"}
{"id":"data-get-2","op":"eval","source":"(get (profile-card \"Ada Lovelace\" \"Mathematician\") 0)"}
{"id":"reset-before-arr","op":"reset"}
{"id":"load-arr","op":"eval","source":"(import arr \"kvist:arr\")","no_print":true,"defer_debug_values":true}
{"id":"arr-fixed-1","op":"eval","source":"(arr.fixed int [1 2 3])"}
{"id":"arr-fixed-2","op":"eval","source":"(arr.fixed int [1 2 3])"}
{"id":"close","op":"close"}
JSONL

KVIST_ROOT="$ROOT/src/kvist" \
    "$compiler" repl "$context_path" \
    --protocol jsonl <"$requests" >"$events"

awk '
function text_field(line, key,    needle, rest) {
    needle = "\"" key "\":\""
    if (index(line, needle) == 0) return ""
    rest = substr(line, index(line, needle) + length(needle))
    sub(/\".*/, "", rest)
    return rest
}
function int_field(line, key,    needle, rest) {
    needle = "\"" key "\":"
    if (index(line, needle) == 0) return 0
    rest = substr(line, index(line, needle) + length(needle))
    sub(/[^0-9].*/, "", rest)
    return rest + 0
}
function bool_field(line, key,    needle, rest) {
    needle = "\"" key "\":"
    if (index(line, needle) == 0) return "false"
    rest = substr(line, index(line, needle) + length(needle))
    return substr(rest, 1, 4) == "true" ? "true" : "false"
}
function phase_ms(line, phase,    needle, rest) {
    needle = "\"phase\":\"" phase "\",\"elapsed_ns\":"
    if (index(line, needle) == 0) return 0
    rest = substr(line, index(line, needle) + length(needle))
    sub(/[^0-9].*/, "", rest)
    return (rest + 0) / 1000000.0
}
BEGIN {
    print "id\tbytes\tfrontend_ms\temission_ms\todin_ms\tworker_load_ms\tnative_ms\ttotal_ms\tfrontend_cache\tnative_cache\texecution_path"
}
/\"kind\":\"timings\"/ {
    printf "%s\t%d\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%s\t%s\t%s\n",
        text_field($0, "id"),
        int_field($0, "generated_bytes"),
        phase_ms($0, "frontend-total"),
        phase_ms($0, "frontend-emission"),
        phase_ms($0, "odin-build"),
        phase_ms($0, "worker-load"),
        phase_ms($0, "native-run"),
        phase_ms($0, "controller-total"),
        bool_field($0, "frontend_cache_hit"),
        bool_field($0, "native_cache_hit"),
        text_field($0, "execution_path")
}
' "$events"
