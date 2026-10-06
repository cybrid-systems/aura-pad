#!/usr/bin/env bash
# M11: Aura-unique features on the notebook stack (docs/m11.md).
#   1. paren balance of robot + m11_*                              -> PAREN_OK
#   2. Soft tests (m11_test.aura -> m11_cases.aura) with
#      AURA_MUTATE_TYPE_GATE=hard                                  -> PAD_M11_TEST_OK
#   3. M11a "undo the robot": a two-define AI proposal lands as ONE typed
#      engine transaction (one composite id), ctrl-z (IN 26) puts engine
#      code + page + stamps back in one key, an arity- or type-broken
#      proposal moves nothing (no half change)        -> M11A_ACC 1..3 OK
#                                                                   -> PAD_M11_UNDO_OK
#   4. M11b engine "who wrote this": robot / pen writes run under
#      mutate:set-agent-fingerprint (kid=1 helper=42 macro=3 law=4);
#      ctrl-o answers from query:node-provenance + the rebind record's
#      reason and agrees with the Soft row stamps, also after ctrl-z
#                                                     -> M11B_ACC 1..3 OK
#                                                                   -> PAD_M11_WHO_OK
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out/m11"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/robot.aura "$ROOT"/soft/pad/eng_who.aura \
  "$ROOT"/soft/pad/m11_test.aura "$ROOT"/soft/pad/m11_cases.aura

echo "smoke_m11: Soft tests (AURA_MUTATE_TYPE_GATE=hard)"
T="$ROOT/out/m11/m11_test.txt"
AURA_MUTATE_TYPE_GATE=hard bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m11_test.aura \
  </dev/null >"$T" 2>"$ROOT/out/m11/m11_test.err"
grep -E '^(M11[A-Z_]*|M11GATE|M11STATS|M11TXN|KEEP robot|DROP robot|REJECT robot|EWHOROWS|TESTS|PAD_M11_TEST)' "$T" || true
if ! grep -q '^PAD_M11_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m11/m11_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m11/m11_test.err" >&2 || true
  echo "smoke_m11: PAD_M11_TEST_FAIL" >&2
  exit 1
fi
if [[ "$(grep -c '^M11 Aura-unique features on Soft tip$' "$T")" -ne 1 ]]; then
  echo "smoke_m11: test file ran more than once" >&2; exit 1
fi

fail=0
for n in 1 2 3; do
  grep -qx "M11A_ACC $n OK" "$T" || { echo "smoke_m11: missing: M11A_ACC $n OK" >&2; fail=1; }
done
for want in 'M11GATE type_gate=hard' 'T A1_ONE_TXN=1 OK' 'T A2_ONE_KEY=1 OK' \
            'T A3_ARITY_CODE_SAME=yes OK' 'T A3_TYPE_DROP=DROP OK' 'T A3_HELLO_NOT_HALF=yes OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m11: missing: $want" >&2; fail=1; }
done
if grep -q '^M11_UNDO_DISAGREE' "$T"; then
  echo "smoke_m11: robot undo disagreed with the engine" >&2; fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m11: PAD_M11_UNDO_OK checks failed" >&2; exit 1
fi
echo "smoke_m11: PAD_M11_UNDO_OK"

fail=0
for n in 1 2 3; do
  grep -qx "M11B_ACC $n OK" "$T" || { echo "smoke_m11: missing: M11B_ACC $n OK" >&2; fail=1; }
done
for want in 'T B1_AUTHORS=42 OK' 'T B1_ROW0_WHO=helper OK' 'T B1_ROW5_WHO=law OK' \
            'T B1_ROWS_DISAGREE=0 OK' 'T B2_UNDO1_ROW0=nobody OK' 'T B2_UNDO1_ROW2=helper OK' \
            'T B3_KID_AFTER=kid-after OK' 'T B3_FORGED_WHO=disagree OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m11: missing: $want" >&2; fail=1; }
done
if grep -q '^M11_WHO_DISAGREE' "$T"; then
  echo "smoke_m11: engine provenance disagreed with the Soft stamps" >&2; fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m11: PAD_M11_WHO_OK checks failed" >&2; exit 1
fi
echo "smoke_m11: PAD_M11_WHO_OK"
