#!/usr/bin/env bash
# M12: the book closes (docs/m12.md / docs/NEXT.md).
#   1. paren balance of book + m12_*                              -> PAREN_OK
#   2. Soft tests (m12_test.aura -> m12_cases.aura) with
#      AURA_MUTATE_TYPE_GATE=hard                                  -> PAD_M12_TEST_OK
#   3. M12.1 std/persist unbound → GAPS persist; Soft uses
#      serialize-workspace / deserialize-workspace                 -> M12_ACC 1 OK
#   4. M12.2 close pad, open again = restore (no set-code guess);
#      same code/page; who still answers (aura#4365/#4367)         -> M12_ACC 2 OK
#                                                                   -> PAD_M12_OK
# Play loop does not load book.aura (key latency unchanged).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out/m12"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/book.aura \
  "$ROOT"/soft/pad/m12_test.aura "$ROOT"/soft/pad/m12_cases.aura \
  "$ROOT"/soft/pad/time.aura "$ROOT"/soft/pad/robot.aura

echo "smoke_m12: Soft tests (AURA_MUTATE_TYPE_GATE=hard)"
T="$ROOT/out/m12/m12_test.txt"
AURA_MUTATE_TYPE_GATE=hard bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m12_test.aura \
  </dev/null >"$T" 2>"$ROOT/out/m12/m12_test.err"
grep -E '^(M12_|GAPS |USED |CLOSE |OPEN |EWHO |M12STATS|TESTS|PAD_M12)' "$T" || true
if ! grep -q '^PAD_M12_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m12/m12_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m12/m12_test.err" >&2 || true
  echo "smoke_m12: PAD_M12_TEST_FAIL" >&2
  exit 1
fi
if [[ "$(grep -c '^M12 the book closes on Soft tip$' "$T")" -ne 1 ]]; then
  echo "smoke_m12: test file ran more than once" >&2; exit 1
fi

fail=0
for n in 1 2; do
  grep -qx "M12_ACC $n OK" "$T" || { echo "smoke_m12: missing: M12_ACC $n OK" >&2; fail=1; }
done
for want in 'GAPS persist' \
            'USED serialize-workspace.deserialize-workspace' \
            'T GAPS=GAPS persist OK' 'T SER=yes OK' 'T DESER=yes OK' 'T NO_PERSIST=yes OK' \
            'T CLOSE=CLOSE OK' 'T CLOSE_SAY=the book is closed, with its story OK' \
            'T AW_FILE=yes OK' 'T PAD_FILE=yes OK' \
            'T OPEN=OPEN OK' 'T CODE=yes OK' 'T PAGE=yes OK' \
            'T WHO0_VERDICT=agree OK' 'T WHO0_HELPER=yes OK' 'T WHO0_BOOK=yes OK' \
            'T WHO2_SAY=yes OK' 'T NO_WHO_DISAGREE=0 OK' 'T NO_BOOK=NOOPEN OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m12: missing: $want" >&2; fail=1; }
done
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m12: PAD_M12_OK checks failed" >&2; exit 1
fi
echo "smoke_m12: PAD_M12_OK"
