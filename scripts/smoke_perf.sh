#!/usr/bin/env bash
# Key-path latency smoke: Soft pad_play stream (edit+snap) must beat
# PAD_PERF_OK threshold (~50ms median/key for the small play buffer).
# See docs/perf.md. Does not need a TTY; PAD_LIVE=0 smoke.sh stays green.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"

soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

echo "smoke_perf: Soft key-path ms/key"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/perf.aura \
  >"$ROOT/out/perf.txt" 2>"$ROOT/out/perf.err"
cat "$ROOT/out/perf.txt"
if soft_errs "$ROOT/out/perf.txt" "$ROOT/out/perf.err"; then
  cat "$ROOT/out/perf.err" >&2 || true
  echo "smoke_perf: Soft error" >&2
  exit 1
fi
grep -qE '^PERF n=' "$ROOT/out/perf.txt" || { echo "smoke_perf: no PERF line" >&2; exit 1; }
grep -q '^PAD_PERF_OK$' "$ROOT/out/perf.txt" || {
  cat "$ROOT/out/perf.err" >&2 || true
  echo "smoke_perf: PAD_PERF_FAIL (see docs/perf.md)" >&2
  exit 1
}
echo "smoke_perf: PAD_PERF_OK"
