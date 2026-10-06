#!/usr/bin/env bash
# M9: workspace notebook (ws.aura) + pen (pen.aura) on Soft tip.
#   1. paren balance of std/ws/pen/m9_* (+ the stack they load) -> PAREN_OK
#   2. Soft tests (m9_test.aura -> m9_cases.aura)               -> PAD_M9_TEST_OK
#      six ROADMAP acceptance items                             -> M9_ACC 1..6 OK
#   3. markers: check / pen verdicts / zero set-code on keys    -> PAD_M9_OK
# Typing stays on the M7 key path (smoke_m7/smoke_perf gate its latency).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out/m9"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/std.aura "$ROOT"/soft/pad/query.aura \
  "$ROOT"/soft/pad/jump.aura "$ROOT"/soft/pad/lc.aura \
  "$ROOT"/soft/pad/ws.aura "$ROOT"/soft/pad/pen.aura \
  "$ROOT"/soft/pad/m9_test.aura "$ROOT"/soft/pad/m9_cases.aura

echo "smoke_m9: Soft tests"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m9_test.aura \
  </dev/null >"$ROOT/out/m9/m9_test.txt" 2>"$ROOT/out/m9/m9_test.err"
T="$ROOT/out/m9/m9_test.txt"
grep -E '^(M9_ACC|M9[A-Z]+ |KEEP pen|DROP pen|TESTS|PAD_M9_TEST)' "$T" || true
if ! grep -q '^PAD_M9_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m9/m9_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m9/m9_test.err" >&2 || true
  echo "smoke_m9: PAD_M9_TEST_FAIL" >&2
  exit 1
fi
# One run only: a second banner means the file was re-run (see docs/m9.md).
if [[ "$(grep -c '^M9 workspace notebook on Soft tip$' "$T")" -ne 1 ]]; then
  echo "smoke_m9: test file ran more than once" >&2; exit 1
fi
checks=$(sed -n 's/^TESTS checks=\([0-9]*\) fail=0$/\1/p' "$T")
if [[ -z "$checks" || "$checks" -lt 100 ]]; then
  echo "smoke_m9: too few checks (${checks:-none})" >&2; exit 1
fi
echo "smoke_m9: PAD_M9_TEST_OK checks=$checks"

fail=0
for n in 1 2 3 4 5 6; do
  grep -qx "M9_ACC $n OK" "$T" || { echo "smoke_m9: missing: M9_ACC $n OK" >&2; fail=1; }
done
for want in \
  'USED define-lookup.query:code.query:ref-counts.query:node-types' \
  'GAPS set-code' \
  'T WS_GAP=gap OK' \
  'T RT_BIG_ROWS=12 OK' \
  'M9CHECK reason=ok soft=hello.bye.add.pet.greet engine=hello.bye.add.pet.greet missing=none extra=none engine_total=6' \
  'M9MARKS hello@0:9.bye@1:9.add@2:9.pet@4:8.greet@5:9' \
  'M9REFS hello=1.bye=1.add=1.pet=1.greet=1' \
  'T CHECK_GUARD_SETCODE=0 OK' \
  'REJECT pen who=helper name=hello reason=not-kind gen+=0 total+=0 say="let'"'"'s use kind words"' \
  'T REJ_COUNT=7 OK' \
  'KEEP pen who=helper name=hello reason=row gen+=1 total+=2 say="helper changed hello"' \
  'DROP pen who=helper name=bye reason=engine-no gen+=0 total+=0 say="aura could not use that change, page put back"' \
  'T PROBE_HEALS=1 OK' \
  'T UNDO_KEEP=ok OK' \
  'T KEYS_SETCODE=0 OK' \
  'T CHECK_AFTER_KEYS=1 OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m9: missing: $want" >&2; fail=1; }
done
grep -qE '^M9STATS .* keys=20 set_code_between_checks=0$' "$T" \
  || { echo "smoke_m9: missing: M9STATS ... set_code_between_checks=0" >&2; fail=1; }
grep -qE '^M9LOAD ms=[0-9]+ rows=12 ' "$T" \
  || { echo "smoke_m9: missing: M9LOAD" >&2; fail=1; }
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m9: PAD_M9_OK checks failed" >&2
  exit 1
fi
grep -E '^M9LOAD ' "$T"
echo "smoke_m9: PAD_M9_OK"
