#!/usr/bin/env bash
# Copyright (c) Andreas Flakstad and Kvist contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

if [[ $# -lt 1 ]]; then
  cat >&2 <<'USAGE'
Usage:
  scripts/particle_stats.sh -- <command> [args...]

Examples:
  scripts/particle_stats.sh -- build/particle-sim
  scripts/particle_stats.sh -- clojure -M:particle-sim

Samples the launched process once per second and prints elapsed seconds, CPU%,
RSS MiB, VSZ MiB, and command name. Close the app window or press Ctrl-C to
stop sampling.
USAGE
  exit 2
fi

if [[ "$1" == "--" ]]; then
  shift
fi

"$@" &
pid=$!
samples_file=$(mktemp "${TMPDIR:-/tmp}/particle-stats.XXXXXX")

cleanup() {
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$samples_file"
}
trap cleanup INT TERM EXIT

printf "pid=%s command=%q" "$pid" "$1"
shift || true
for arg in "$@"; do
  printf " %q" "$arg"
done
printf "\n"
printf "%8s %8s %10s %10s %s\n" "elapsed" "cpu%" "rss_mib" "vsz_mib" "command"

start=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
  now=$(date +%s)
  elapsed=$((now - start))
  sample=$(ps -o %cpu= -o rss= -o vsz= -o comm= -p "$pid" || true)
  if [[ -n "$sample" ]]; then
    awk -v elapsed="$elapsed" -v samples_file="$samples_file" '
      {
        cpu=$1
        rss=$2 / 1024
        vsz=$3 / 1024
        $1=$2=$3=""
        sub(/^ +/, "", $0)
        printf "%d %.3f %.3f %.3f\n", elapsed, cpu, rss, vsz >> samples_file
        printf "%8ds %8.1f %10.1f %10.1f %s\n", elapsed, cpu, rss, vsz, $0
      }
    ' <<<"$sample"
  fi
  sleep 1
done

wait "$pid" 2>/dev/null || true
if [[ -s "$samples_file" ]]; then
  awk '
    {
      count += 1
      cpu_sum += $2
      if ($2 > cpu_max) cpu_max = $2
      if ($3 > rss_max) rss_max = $3
      if ($4 > vsz_max) vsz_max = $4
      last_elapsed = $1
    }
    END {
      printf "summary samples=%d elapsed_s=%d avg_cpu=%.1f max_cpu=%.1f max_rss_mib=%.1f max_vsz_mib=%.1f\n",
        count, last_elapsed, cpu_sum / count, cpu_max, rss_max, vsz_max
    }
  ' "$samples_file"
fi
rm -f "$samples_file"
trap - INT TERM EXIT
