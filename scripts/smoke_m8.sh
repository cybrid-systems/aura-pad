#!/usr/bin/env bash
# M8: kid onboarding card + intent worldline.
#   1. paren balance of card/goal/m8_* + fixtures     -> PAREN_OK
#   2. host model CARD scores                         -> PAD_M8_MODEL_OK
#   3. Soft tests (m8_test.aura)                      -> PAD_M8_TEST_OK
#   4. play first frame welcome + goal: empty/set     -> PAD_M8_PLAY_OK
#   5. fixture race + gate + undo                     -> PAD_M8_OK
# Key-path latency stays under M7 gates (smoke_perf via smoke_m7).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out/m8"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/card.aura "$ROOT"/soft/pad/goal.aura \
  "$ROOT"/soft/pad/goal_p1.aura "$ROOT"/soft/pad/goal_p2.aura \
  "$ROOT"/soft/pad/m8_test.aura "$ROOT"/soft/pad/m8_smoke.aura \
  "$ROOT"/soft/pad/keys.aura "$ROOT"/soft/pad/play.aura \
  "$ROOT"/soft/pad/fixtures/m8/*.lambda

python3 "$ROOT/scripts/goal_model.py" --check | tee "$ROOT/out/m8/model.txt"
grep -q '^PAD_M8_MODEL_OK$' "$ROOT/out/m8/model.txt"

echo "smoke_m8: Soft tests"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m8_test.aura \
  >"$ROOT/out/m8/m8_test.txt" 2>"$ROOT/out/m8/m8_test.err"
T="$ROOT/out/m8/m8_test.txt"
grep -E '^(TESTS|T CARD_|T GOAL_|T SCORE_|T TAG_|PAD_M8_TEST)' "$T" || true
if ! grep -q '^PAD_M8_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m8/m8_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m8/m8_test.err" >&2 || true
  echo "smoke_m8: PAD_M8_TEST_FAIL" >&2
  exit 1
fi
checks=$(sed -n 's/^TESTS checks=\([0-9]*\) fail=0$/\1/p' "$T")
if [[ -z "$checks" || "$checks" -lt 30 ]]; then
  echo "smoke_m8: too few checks (${checks:-none})" >&2; exit 1
fi
for want in 'T CARD_FIRST=1 OK' 'T GOAL_NONE=no-goal OK' 'T SCORE_MAIN=27 OK' \
            'T SCORE_BETTER=31 OK' 'T TAG_BETTER=goal_keep OK' \
            'T WORD_CAP=exec OK' 'T UNDO_FAIL=goal_undo_fail OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m8: test missing: $want" >&2; exit 1; }
done
echo "smoke_m8: PAD_M8_TEST_OK checks=$checks"

echo "smoke_m8: play welcome card + goal: command"
{
  echo "KEY goal:"
  echo "KEY goal:hi aura"
  echo "QUIT"
} >"$ROOT/out/m8/play.in"
bash "$ROOT/scripts/soft_play.sh" <"$ROOT/out/m8/play.in" \
  >"$ROOT/out/m8/play.txt" 2>"$ROOT/out/m8/play.err"
if soft_errs "$ROOT/out/m8/play.txt" "$ROOT/out/m8/play.err"; then
  cat "$ROOT/out/m8/play.err" >&2; exit 1
fi
# First SNAP carries welcome card words; empty goal: rejects; goal:hi aura sets.
python3 - "$ROOT/out/m8/play.txt" << 'PY'
import re, sys
text = open(sys.argv[1]).read()
blocks = text.split("SNAP v1 pad\n")[1:]
assert blocks, "no SNAP"
first = blocks[0]
assert "welcome to aura pad" in first, first[:200]
assert "type goal:hi aura to try" in first, first[:200]
says = re.findall(r"^SAY (.*)$", text, re.M)
assert any("tell me what the page should say" in s for s in says), says
assert any(s.startswith("goal set: hi aura") for s in says), says
print("PAD_M8_PLAY_OK")
PY

echo "smoke_m8: fixture race + gate + undo"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m8_smoke.aura \
  >"$ROOT/out/m8/m8_smoke.txt" 2>"$ROOT/out/m8/m8_smoke.err"
cat "$ROOT/out/m8/m8_smoke.txt"
if [[ -s "$ROOT/out/m8/m8_smoke.err" ]]; then cat "$ROOT/out/m8/m8_smoke.err" >&2; fi
S="$ROOT/out/m8/m8_smoke.txt"
fail=0
for want in \
  'CARD a=27 b=14 KEEP=a say="a is closer"' \
  'DROP kind=goal reason=lower-score-rollback score=14' \
  'CARD a=27 b=27 KEEP=a say="same score, keeping yours"' \
  'DROP kind=goal reason=tie score=27' \
  'CARD a=27 b=31 KEEP=b say="b is closer"' \
  'KEEP kind=goal reason=higher-score-stamp score=31' \
  'TAPE kind=goal text=hi|aura score=31' \
  'GATE reject reason=gate word=set!' \
  'GATE reject reason=kind word=stupid' \
  'REJECT mid=8 reason=not-allowed' \
  'HEAL name=pd:goal reason=probe why=not-a-plan' \
  'UNDO kind=goal from=31 to=27 want=27' \
  'KEEPS=1 OK' 'DROPS=2 OK' 'UNDOS=1 OK' \
  'PAD_M8_OK'; do
  grep -qF -- "$want" "$S" || { echo "smoke_m8: missing: $want" >&2; fail=1; }
done
grep -E -q 'WORLD line=(host-sequential|fiber_live)' "$S" || fail=1
if grep -q 'WORLD line=fiber_live' "$S"; then
  python3 - "$S" << 'PY' || fail=1
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"WORLD line=fiber_live backend=(\d+) joins=(\d+)/(\d+)", text)
if not m or m.group(2) != m.group(3) or int(m.group(1)) <= 0 or int(m.group(2)) <= 0:
    sys.exit(1)
PY
fi
if grep -q '_FAIL\|WANT=' "$S"; then fail=1; fi
if soft_errs "$S" "$ROOT/out/m8/m8_smoke.err"; then fail=1; fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m8: PAD_M8_OK checks failed" >&2
  exit 1
fi
echo "smoke_m8: PAD_M8_OK"
