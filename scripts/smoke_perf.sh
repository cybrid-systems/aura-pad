#!/usr/bin/env bash
# Key-path latency smoke: Soft pad_play stream (edit+snap) must beat
# PAD_PERF_OK threshold (<50 ms/key on the small play page) and, from M7,
# PAD_M7_PERF_OK (twelve-line page: <50 ms/key and >=2x faster insert
# than the M6 whole-page path). Timing is wall clock on a shared box, so
# one retry is allowed and reported (attempt=2); two misses fail.
# Then the Emacs-port check (soft/pad/emacs_test.aura, docs/perf-emacs.md):
# fast paths == references (commands, scanner, every frame vs the M6
# oracle) and 12-row insert/cursor under one 60 fps frame (16 ms) ->
# PAD_PERF_EMACS_OK. A correctness failure never gets a retry.
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

run_emacs() {
  bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/emacs_test.aura \
    >"$ROOT/out/perf_emacs.txt" 2>"$ROOT/out/perf_emacs.err"
  grep -E '^(ET_|PERF_EMACS|EMACS_TEST|PAD_PERF_EMACS)' "$ROOT/out/perf_emacs.txt" || true
  if soft_errs "$ROOT/out/perf_emacs.txt" "$ROOT/out/perf_emacs.err"; then
    cat "$ROOT/out/perf_emacs.err" >&2 || true
    echo "smoke_perf: Soft error in emacs_test" >&2
    exit 1
  fi
  # correctness first: any diff is a hard failure, no retry
  if ! grep -qE '^EMACS_TEST checks=[0-9]+ fail=0$' "$ROOT/out/perf_emacs.txt"; then
    echo "smoke_perf: PAD_PERF_EMACS_FAIL (fast path != reference)" >&2
    exit 1
  fi
  grep -q '^PAD_PERF_EMACS_OK$' "$ROOT/out/perf_emacs.txt"
}

echo "smoke_perf: Emacs-port fast paths (docs/perf-emacs.md)"
eattempt=1
if ! run_emacs; then
  eattempt=2
  echo "smoke_perf: emacs retry (wall-clock noise on a shared box)"
  run_emacs || { echo "smoke_perf: PAD_PERF_EMACS_FAIL (over the 16 ms frame)" >&2; exit 1; }
fi
echo "smoke_perf: PAD_PERF_EMACS_OK attempt=$eattempt"
