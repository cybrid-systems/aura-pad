#!/usr/bin/env bash
# M13: aura notebook pad (docs/m13.md). Marker PAD_M13_OK.
#   1. paren balance                                              -> PAREN_OK
#   2. Soft tests (AURA notebook: HL tape, jump, hygienic GAPS,
#      fixture race DROP)                                         -> PAD_M13_TEST_OK
#   3. M13_ACC 1..4                                               -> PAD_M13_OK
# Play loop does not load aura_pad.aura (key latency unchanged).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out/m13"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/aura_pad.aura \
  "$ROOT"/soft/pad/m13_test.aura "$ROOT"/soft/pad/m13_cases.aura \
  "$ROOT"/soft/pad/hl.aura "$ROOT"/soft/pad/jump.aura

echo "smoke_m13: Soft tests"
T="$ROOT/out/m13/m13_test.txt"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m13_test.aura \
  </dev/null >"$T" 2>"$ROOT/out/m13/m13_test.err"
grep -E '^(M13_|GAPS |FIXTURE |M13STATS|TESTS|PAD_M13)' "$T" || true
if ! grep -q '^PAD_M13_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m13/m13_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m13/m13_test.err" >&2 || true
  echo "smoke_m13: PAD_M13_TEST_FAIL" >&2
  exit 1
fi
if [[ "$(grep -c '^M13 aura notebook on Soft tip$' "$T")" -ne 1 ]]; then
  echo "smoke_m13: test file ran more than once" >&2; exit 1
fi
fail=0
for n in 1 2 3 4; do
  grep -qx "M13_ACC $n OK" "$T" || { echo "smoke_m13: missing: M13_ACC $n OK" >&2; fail=1; }
done
for want in 'GAPS hygienic-play' \
            'T KINDS=PKSN OK' 'T GOTO_SOFT=ok OK' 'T WS_LOAD=yes OK' \
            'T REFUSE=REFUSE OK' 'T GOOD=KEEP OK' 'T BAD=DROP OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m13: missing: $want" >&2; fail=1; }
done
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m13: PAD_M13_OK checks failed" >&2; exit 1
fi
echo "smoke_m13: PAD_M13_OK"
