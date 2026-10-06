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
#   5. M11c "why did it break": a refused proposal is replayed one rebind
#      at a time; aura's own reason (type / arity / unbound / brackets,
#      or a blamed caller line) becomes one kid sentence in the say line;
#      false "unbound" diagnostics for notebook defines are dropped
#      (aura#4363)                                    -> M11C_ACC 1..3 OK
#                                                                   -> PAD_M11_WHY_OK
#   6. M11d blast radius card: the proposal waits in a snapshot, the say
#      line lists the places it would move (Soft call sites == query:calls,
#      dirty defines == the changed names), enter keeps, ctrl-z says no
#                                                     -> M11D_ACC 1..3 OK
#                                                                   -> PAD_M11_BLAST_OK
#   7. M11e time machine: every KEEP is a step (ast:snapshot after it);
#      ctrl-t / ctrl-n step back / forward (ast:diff names == the names the
#      skipped steps changed, code == the step's code); save =
#      serialize-workspace + sidecar, open = deserialize-workspace (no
#      set-code) with who/why recovered from log reasons + pad stamps
#      (aura#4365, aura#4366)                         -> M11E_ACC 1..3 OK
#                                                                   -> PAD_M11_TIME_OK
#   8. M11f sandbox worlds: each AI idea is tried in its own child world
#      (workspace :create / :switch, one typed-mutate-atomic, goal checks
#      run there); root is healed after every idea (aura#4368); only an
#      idea that beats the page comes back, as a robot KEEP (rebind, never
#      workspace :merge)                               -> M11F_ACC 1..2 OK
#                                                                   -> PAD_M11_WORLD_OK
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out/m11"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/robot.aura "$ROOT"/soft/pad/eng_who.aura "$ROOT"/soft/pad/why.aura \
  "$ROOT"/soft/pad/blast.aura "$ROOT"/soft/pad/time.aura "$ROOT"/soft/pad/ws.aura \
  "$ROOT"/soft/pad/world.aura "$ROOT"/soft/pad/m11_test.aura "$ROOT"/soft/pad/m11_cases.aura \
  "$ROOT"/soft/pad/m11e_cases.aura "$ROOT"/soft/pad/m11f_cases.aura

echo "smoke_m11: Soft tests (AURA_MUTATE_TYPE_GATE=hard)"
T="$ROOT/out/m11/m11_test.txt"
AURA_MUTATE_TYPE_GATE=hard bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m11_test.aura \
  </dev/null >"$T" 2>"$ROOT/out/m11/m11_test.err"
grep -E '^(M11[A-Z_]*|M11GATE|M11STATS|M11TXN|KEEP robot|DROP robot|REJECT robot|CARD robot|BLAST|EWHOROWS|TIME|OPEN|SAVE|WORLD|WIN|NOWIN|TESTS|PAD_M11_TEST)' "$T" || true
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

fail=0
for n in 1 2 3; do
  grep -qx "M11C_ACC $n OK" "$T" || { echo "smoke_m11: missing: M11C_ACC $n OK" >&2; fail=1; }
done
for want in "T C2_ARITY_SAY=the helper's bye gives hello 2 things, it wants 1 OK" \
            "T C2_TYPE_SAY=the helper's greet used a number where words go OK" \
            "T C2_CALLER_SAY=the helper's hello now wants 2 things, but bye gives it 1 OK" \
            "T C2_ONE_HEAL=1 OK" "T C2_CODE_SAME=yes OK" "T C3_NO_FALSE_WARN=0 OK" \
            "T C3_CALLER_TYPE_SAY=the helper's bye does not fit (bye 4) OK"; do
  grep -qF -- "$want" "$T" || { echo "smoke_m11: missing: $want" >&2; fail=1; }
done
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m11: PAD_M11_WHY_OK checks failed" >&2; exit 1
fi
echo "smoke_m11: PAD_M11_WHY_OK"

fail=0
for n in 1 2 3; do
  grep -qx "M11D_ACC $n OK" "$T" || { echo "smoke_m11: missing: M11D_ACC $n OK" >&2; fail=1; }
done
for want in 'T D1_SITES=hello:3/4:+1.bye:2/2:+0 OK' 'T D1_VERDICT=agree OK' 'T D1_PAGE_WAITS=yes OK' \
            'T D1_ENGINE_HAS_IT=yes OK' 'T D2_CODE_BACK=yes OK' 'T D2_VERDICT=agree OK' \
            "T D2_SAY=changing add moves 3 places: greet, (greet (add 1 2)), (add 2 3). enter keeps, ctrl-z says no OK"; do
  grep -qF -- "$want" "$T" || { echo "smoke_m11: missing: $want" >&2; fail=1; }
done
if grep -q '^M11_BLAST_DISAGREE' "$T"; then
  echo "smoke_m11: blast card disagreed with the engine" >&2; fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m11: PAD_M11_BLAST_OK checks failed" >&2; exit 1
fi
echo "smoke_m11: PAD_M11_BLAST_OK"

fail=0
for n in 1 2 3; do
  grep -qx "M11E_ACC $n OK" "$T" || { echo "smoke_m11: missing: M11E_ACC $n OK" >&2; fail=1; }
done
for want in 'T E1_BACK1=TIME from=3 to=2 eng=add soft=add code=yes verdict=agree OK' \
            'T E1_BACK2_CODE=yes OK' 'T E1_BACK2_PAGE=yes OK' 'T E1_FWD2_CODE=yes OK' \
            'T E1_JUMP=TIME from=3 to=1 eng=hello.bye.add soft=hello.bye.add code=yes verdict=agree OK' \
            'T E2_BRANCH=start | [helper: swap] OK' 'T E3_OPEN=OPEN OK' 'T E3_CODE=yes OK' \
            'T E3_PAGE=yes OK' 'T E3_WHO0_VERDICT=agree OK' 'T E3_WHO0_REOPENED=yes OK' \
            'T E3_BACK_CODE=yes OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m11: missing: $want" >&2; fail=1; }
done
if grep -q '^M11_TIME_DISAGREE' "$T"; then
  echo "smoke_m11: time machine disagreed with the engine" >&2; fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m11: PAD_M11_TIME_OK checks failed" >&2; exit 1
fi
echo "smoke_m11: PAD_M11_TIME_OK"

fail=0
for n in 1 2; do
  grep -qx "M11F_ACC $n OK" "$T" || { echo "smoke_m11: missing: M11F_ACC $n OK" >&2; fail=1; }
done
for want in 'T F1_TAG=WIN OK' 'T F1_VERDICT=agree OK' 'T F1_ROOT_SAME_DURING=yes OK' \
            'T F1_IDEA1_SCORE=3 OK' 'T F1_IDEA1_ENG=hello OK' 'T F1_IDEA3=refused OK' \
            'T F1_ROOT_CURRENT=0 OK' 'T F1_HELLO_ROOT=6 OK' 'T F1_UNDO_HELLO=4 OK' \
            'T F2_TAG=NOWIN OK' 'T F2_CODE_SAME=yes OK' 'T F2_GREET_ROOT=2 OK' 'T F2_ROOT_CURRENT=0 OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m11: missing: $want" >&2; fail=1; }
done
if grep -q '^M11_WORLD_DISAGREE' "$T"; then
  echo "smoke_m11: sandbox worlds disagreed with the engine" >&2; fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m11: PAD_M11_WORLD_OK checks failed" >&2; exit 1
fi
echo "smoke_m11: PAD_M11_WORLD_OK"
