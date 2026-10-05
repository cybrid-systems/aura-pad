#!/usr/bin/env bash
# Key-path latency smoke: Soft pad_play stream (edit+snap) must beat
# PAD_PERF_OK threshold (<50 ms/key on the small play page) and, from M7,
# PAD_M7_PERF_OK (twelve-line page: <50 ms/key and >=2x faster insert
# than the M6 whole-page path). Timing is wall clock on a shared box, so
# one retry is allowed and reported (attempt=2); two misses fail.
# See docs/perf.md. Does not need a TTY; PAD_LIVE=0 smoke.sh stays green.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"

soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

run_perf() {
  bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/perf.aura \
    >"$ROOT/out/perf.txt" 2>"$ROOT/out/perf.err"
  cat "$ROOT/out/perf.txt"
  if soft_errs "$ROOT/out/perf.txt" "$ROOT/out/perf.err"; then
    cat "$ROOT/out/perf.err" >&2 || true
    echo "smoke_perf: Soft error" >&2
    exit 1
  fi
  grep -qE '^PERF n=' "$ROOT/out/perf.txt" || { echo "smoke_perf: no PERF line" >&2; exit 1; }
  grep -q '^PAD_PERF_OK$' "$ROOT/out/perf.txt" && grep -q '^PAD_M7_PERF_OK$' "$ROOT/out/perf.txt"
}

echo "smoke_perf: Soft key-path ms/key"
attempt=1
if ! run_perf; then
  attempt=2
  echo "smoke_perf: retry (wall-clock noise on a shared box)"
  run_perf || {
    cat "$ROOT/out/perf.err" >&2 || true
    echo "smoke_perf: PAD_PERF_FAIL (see docs/perf.md)" >&2
    exit 1
  }
fi
echo "smoke_perf: PAD_PERF_OK PAD_M7_PERF_OK attempt=$attempt"
