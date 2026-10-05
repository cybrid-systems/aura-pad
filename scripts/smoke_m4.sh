#!/usr/bin/env bash
# M4: two pads, find / replace, record / play, buffer-law race, macro propose.
#   1. paren balance of every Soft file + every fixture lambda (Aura #4342)
#                                                -> PAREN_OK
#   2. host Python model re-computes every number m4_test.aura asserts
#                                                -> PAD_M4_MODEL_OK
#   3. Soft tests (m4_test.aura, >= 250 checks)   -> PAD_M4_TEST_OK
#   4. law race + macro race + macro undo         -> PAD_M4_OK
#   5. optional live MiniMax --macro propose      -> PAD_M4_LIVE_OK, or
#      PAD_M4_LIVE_SKIP when PAD_LIVE=0 or no key.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"

python3 "$ROOT/scripts/paren_check.py" "$ROOT"/soft/pad/*.aura "$ROOT"/soft/pad/fixtures/m4/*.lambda
python3 "$ROOT/scripts/m4_model.py" --check >"$ROOT/out/m4_model.txt"
tail -1 "$ROOT/out/m4_model.txt"
grep -q '^PAD_M4_MODEL_OK$' "$ROOT/out/m4_model.txt" || { cat "$ROOT/out/m4_model.txt" >&2; exit 1; }

soft_errs() {
  grep -qiE 'error:|unbound variable' "$@"
}

echo "smoke: m4 tests"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m4_test.aura \
  >"$ROOT/out/m4_test.txt" 2>"$ROOT/out/m4_test.err"
T="$ROOT/out/m4_test.txt"
grep -E '^TESTS ' "$T" || true
if ! grep -q '^PAD_M4_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m4_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m4_test.err" >&2 || true
  echo "smoke_m4: PAD_M4_TEST_FAIL" >&2
  exit 1
fi
checks=$(sed -n 's/^TESTS checks=\([0-9]*\) fail=0$/\1/p' "$T")
if [[ -z "$checks" || "$checks" -lt 250 ]]; then
  echo "smoke_m4: too few checks (${checks:-none})" >&2
  exit 1
fi
for want in 'T FIND_COW=not-found OK' 'T FIND_EMPTY=empty-needle OK' 'T ALL_MANY=too-many OK' \
  'T REP_MEAN=not-kind OK' 'T SWITCH_ZOO=no-buffer OK' 'T MACRO_FULL=macro-full OK' \
  'T PLAN_COUNT=47 OK' 'T FX_SMART=51 OK' \
  'REJECT mid=4 reason=not-found cmd=find:cow step=1 pad=story slot=test say="could not find that word"'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m4: test missing: $want" >&2; exit 1; }
done
echo "smoke_m4: PAD_M4_TEST_OK checks=$checks"

echo "smoke: m4 law race + macro race + undo"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m4_smoke.aura \
  >"$ROOT/out/m4_smoke.txt" 2>"$ROOT/out/m4_smoke.err"
cat "$ROOT/out/m4_smoke.txt"
if [[ -s "$ROOT/out/m4_smoke.err" ]]; then
  cat "$ROOT/out/m4_smoke.err" >&2
fi
S="$ROOT/out/m4_smoke.txt"
fail=0
for want in \
  'RACE law base=stop-3:-8 trial=wrap-3:14' \
  'KEEP kind=law law=wrap-3 reason=higher-score-stamp score=14' \
  'RACE law base=wrap-3:14 trial=wrap-9:-7' \
  'DROP kind=law law=wrap-9 reason=lower-score-rollback score=-7' \
  'MAIN macro start=30 law=wrap-3' \
  'SCORE total=30 start=60 keys=-30 rejects=-0 dist=-0' \
  'REJECT mid=4 reason=nothing-to-undo cmd=macro-undo' \
  'GATE reject reason=gate word=set!' \
  'GATE reject reason=kind word=stupid say="let us use kind words"' \
  'HEAL name=pd:macro reason=probe why=bad-token' \
  'REJECT mid=4 reason=empty-needle cmd=find: step=1 pad=story slot=pd:macro say="tell me a word to find first"' \
  'REJECT mid=4 reason=not-found cmd=find:cow step=2' \
  'REJECT mid=4 reason=too-many cmd=replace-all:a=e step=3' \
  'REJECT mid=4 reason=no-buffer cmd=switch:zoo step=4' \
  'REJECTS kind=macro total=6 shown=4' \
  'RACE macro base=30 trial=18' \
  'DROP kind=macro reason=lower-score-rollback score=18' \
  'REJECT mid=4 reason=not-found cmd=play step=6' \
  'KEEP kind=macro reason=higher-score-stamp score=44 say="the new macro wins, 44 beats 30"' \
  'RACE macro base=44 trial=51' \
  'TAPE pad=story* lines=3 text=a.dog|the.dog.ran|they.had.fun' \
  'TAPE law=wrap-3 find=none macro=0 kill=|they.had.fun' \
  'SCORE total=51 start=60 keys=-9 rejects=-0 dist=-0 say="9 keys, 0 oops, 0 letters off"' \
  'DROP kind=macro reason=tie-is-not-better-rollback score=51 say="same score, we keep the old macro"' \
  'UNDO kind=macro from=51 to=44 want=44 left=1' \
  'KEEPS=3 OK' 'DROPS=2 OK' 'UNDOS=1 OK' 'LAW_KEEPS=1 OK' 'LAW_DROPS=1 OK' \
  'PAD_M4_OK'; do
  grep -qF -- "$want" "$S" || { echo "smoke_m4: missing: $want" >&2; fail=1; }
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
if soft_errs "$S" "$ROOT/out/m4_smoke.err"; then fail=1; fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m4: PAD_M4_OK checks failed" >&2
  exit 1
fi
echo "smoke_m4: PAD_M4_OK"

if [[ "${PAD_LIVE:-1}" != "1" ]]; then
  echo "PAD_M4_LIVE_SKIP reason=PAD_LIVE=0"
  exit 0
fi
if ! python3 "$ROOT/scripts/propose_minimax.py" --check 2>/dev/null; then
  echo "PAD_M4_LIVE_SKIP reason=no-key"
  exit 0
fi
echo "smoke: m4 live MiniMax story macro propose"
live="$ROOT/out/live_macro.lambda"
rm -f "$live"
if ! python3 "$ROOT/scripts/propose_minimax.py" --macro "$live" 1 "m4 smoke" \
    >/dev/null 2>"$ROOT/out/m4_live_propose.stderr"; then
  cat "$ROOT/out/m4_live_propose.stderr" >&2 || true
  echo "PAD_M4_LIVE_FAIL (host propose)" >&2
  exit 1
fi
cat "$ROOT/out/m4_live_propose.stderr" >&2 || true
test -s "$live"
echo "LIVE_MACRO $(head -c 400 "$live" | tr -d '\n')"
PAD_PROPOSE_FILE="/workspace/aura-pad/out/live_macro.lambda" \
  bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m4_live.aura \
  >"$ROOT/out/m4_live.txt" 2>"$ROOT/out/m4_live.err"
cat "$ROOT/out/m4_live.txt"
if [[ -s "$ROOT/out/m4_live.err" ]]; then
  cat "$ROOT/out/m4_live.err" >&2
fi
if ! grep -q 'PAD_M4_LIVE_OK' "$ROOT/out/m4_live.txt" \
   || soft_errs "$ROOT/out/m4_live.txt" "$ROOT/out/m4_live.err"; then
  echo "PAD_M4_LIVE_FAIL" >&2
  exit 1
fi
echo "PAD_M4_LIVE_OK"
