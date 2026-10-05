#!/usr/bin/env bash
# M3.5 finer editor commands + tests.
#   1. paren balance of every Soft file (Aura #4342: unbalanced ")" in a
#      loaded file silently truncates it)        -> PAREN_OK
#   2. host Python model of the editor vs fixtures/m35/expect.json
#                                                -> PAD_MODEL_OK
#   3. Soft unit-ish tests (m35_test.aura)       -> PAD_TEST_OK
#   4. goal3 helper race + world undo (fixtures) -> PAD_M35_OK
#   5. optional live MiniMax --helper3 propose   -> PAD_M35_LIVE_OK, or
#      PAD_M35_LIVE_SKIP when PAD_LIVE=0 or no key.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"

python3 "$ROOT/scripts/paren_check.py" "$ROOT"/soft/pad/*.aura
python3 "$ROOT/scripts/edit_model.py" --check >"$ROOT/out/m35_model.txt"
tail -1 "$ROOT/out/m35_model.txt"
grep -q '^PAD_MODEL_OK$' "$ROOT/out/m35_model.txt" || { cat "$ROOT/out/m35_model.txt" >&2; exit 1; }

soft_errs() {
  grep -qiE 'error:|unbound variable' "$@"
}

echo "smoke: m35 unit tests"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m35_test.aura \
  >"$ROOT/out/m35_test.txt" 2>"$ROOT/out/m35_test.err"
T="$ROOT/out/m35_test.txt"
grep -E '^TESTS ' "$T" || true
if ! grep -q '^PAD_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m35_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m35_test.err" >&2 || true
  echo "smoke_m35: PAD_TEST_FAIL" >&2
  exit 1
fi
checks=$(sed -n 's/^TESTS checks=\([0-9]*\) fail=0$/\1/p' "$T")
if [[ -z "$checks" || "$checks" -lt 150 ]]; then
  echo "smoke_m35: too few checks (${checks:-none})" >&2
  exit 1
fi
echo "smoke_m35: PAD_TEST_OK checks=$checks"

echo "smoke: m35 goal3 helper race + world undo"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m35_smoke.aura \
  >"$ROOT/out/m35_smoke.txt" 2>"$ROOT/out/m35_smoke.err"
cat "$ROOT/out/m35_smoke.txt"
if [[ -s "$ROOT/out/m35_smoke.err" ]]; then
  cat "$ROOT/out/m35_smoke.err" >&2
fi
S="$ROOT/out/m35_smoke.txt"
fail=0
for want in \
  'MAIN helper start=28' \
  'SCORE total=28 start=60 keys=-14 rejects=-0 dist=-18' \
  'REJECT mid=35 reason=nothing-to-undo cmd=helper-undo' \
  'GATE reject reason=gate word=define' \
  'HEAL name=pd:helper reason=probe why=bad-token' \
  'REJECT mid=35 reason=nothing-to-undo cmd=undo step=1 slot=pd:helper say="nothing to take back yet"' \
  'REJECT mid=35 reason=nothing-to-yank cmd=yank step=2' \
  'REJECT mid=35 reason=no-mark cmd=kill-region step=3' \
  'REJECT mid=35 reason=no-indent cmd=dedent step=4' \
  'REJECTS kind=helper total=5 shown=4' \
  'RACE helper base=28 trial=11' \
  'DROP kind=helper reason=lower-score-rollback score=11' \
  'RACE helper base=28 trial=43' \
  'KEEP kind=helper reason=higher-score-stamp score=43' \
  'RACE helper base=43 trial=43' \
  'DROP kind=helper reason=tie-is-not-better-rollback score=43' \
  'RACE helper base=43 trial=45' \
  'TAPE lines=3 line=2 col=3 text=hi|..aura|pad view=hi|..aura|pad^ kill=nwn undo=8 slot=pd:helper' \
  'SCORE total=45 start=60 keys=-15 rejects=-0 dist=-0 say="15 keys, 0 oops, 0 letters off"' \
  'UNDO kind=helper from=45 to=43 want=43 left=1' \
  'UNDO kind=helper from=43 to=28 want=28 left=0' \
  'RACE helper base=28 trial=45' \
  'KEEPS=3 OK' 'DROPS=2 OK' 'UNDOS=2 OK' \
  'PAD_M35_OK'; do
  grep -qF -- "$want" "$S" || { echo "smoke_m35: missing: $want" >&2; fail=1; }
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
if soft_errs "$S" "$ROOT/out/m35_smoke.err"; then fail=1; fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m35: PAD_M35_OK checks failed" >&2
  exit 1
fi
echo "smoke_m35: PAD_M35_OK"

if [[ "${PAD_LIVE:-1}" != "1" ]]; then
  echo "PAD_M35_LIVE_SKIP reason=PAD_LIVE=0"
  exit 0
fi
if ! python3 "$ROOT/scripts/propose_minimax.py" --check 2>/dev/null; then
  echo "PAD_M35_LIVE_SKIP reason=no-key"
  exit 0
fi
echo "smoke: m35 live MiniMax goal3 helper propose"
live="$ROOT/out/live_helper3.lambda"
rm -f "$live"
if ! python3 "$ROOT/scripts/propose_minimax.py" --helper3 "$live" 1 "m35 smoke" \
    >/dev/null 2>"$ROOT/out/m35_live_propose.stderr"; then
  cat "$ROOT/out/m35_live_propose.stderr" >&2 || true
  echo "PAD_M35_LIVE_FAIL (host propose)" >&2
  exit 1
fi
cat "$ROOT/out/m35_live_propose.stderr" >&2 || true
test -s "$live"
echo "LIVE_HELPER3 $(head -c 300 "$live" | tr -d '\n')"
PAD_PROPOSE_FILE="/workspace/aura-pad/out/live_helper3.lambda" \
  bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m35_live.aura \
  >"$ROOT/out/m35_live.txt" 2>"$ROOT/out/m35_live.err"
cat "$ROOT/out/m35_live.txt"
if [[ -s "$ROOT/out/m35_live.err" ]]; then
  cat "$ROOT/out/m35_live.err" >&2
fi
if ! grep -q 'PAD_M35_LIVE_OK' "$ROOT/out/m35_live.txt" \
   || soft_errs "$ROOT/out/m35_live.txt" "$ROOT/out/m35_live.err"; then
  echo "PAD_M35_LIVE_FAIL" >&2
  exit 1
fi
echo "PAD_M35_LIVE_OK"
