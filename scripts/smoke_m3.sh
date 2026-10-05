#!/usr/bin/env bash
# M3 multi-line buffer + command-helper propose. Fixtures (no HTTP) →
# PAD_M3_OK. Then an optional live MiniMax helper propose (--helper):
# PAD_M3_LIVE_OK, or PAD_M3_LIVE_SKIP when PAD_LIVE=0 or no key.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"
echo "smoke: m3 fixture"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m3_smoke.aura \
  >"$ROOT/out/m3_smoke.txt" 2>"$ROOT/out/m3_smoke.err"
cat "$ROOT/out/m3_smoke.txt"
if [[ -s "$ROOT/out/m3_smoke.err" ]]; then
  cat "$ROOT/out/m3_smoke.err" >&2
fi
T="$ROOT/out/m3_smoke.txt"
fail=0
for want in \
  'START_TEXT=nwn OK' \
  'OP_PREV_TOP=no-line OK' \
  'OP_LEFT_HOME=too-far OK' \
  'OP_KILL_EMPTY=empty-buf OK' \
  'OP_OPEN=hi|nwn@0,2 OK' \
  'MAIN helper start=27' \
  'TAPE lines=2 line=1 col=2 text=hi|au keys=7 rejects=0 dist=2 score=27 slot=pd:hshadow' \
  'GATE reject reason=gate word=set!' \
  'GATE reject reason=gate word=eval' \
  'HEAL name=pd:helper reason=probe why=not-a-plan' \
  'REJECT mid=3 reason=empty-buf cmd=kill-line' \
  'REJECT mid=3 reason=too-far cmd=left' \
  'REJECT mid=3 reason=no-line cmd=next-line' \
  'RACE helper base=27 trial=14' \
  'DROP kind=helper reason=lower-score-rollback score=14' \
  'RACE helper base=27 trial=27' \
  'DROP kind=helper reason=tie-is-not-better-rollback score=27' \
  'RACE helper base=27 trial=31' \
  'KEEP kind=helper reason=higher-score-stamp score=31' \
  'TAPE lines=2 line=1 col=4 text=hi|aura keys=9 rejects=0 dist=0 score=31 slot=pd:helper' \
  'RACE helper base=31 trial=31' \
  'HEAL name=pd:helper reason=score' \
  'PROPOSE kind=helper tag=helper_reject' \
  'PROPOSE kind=helper tag=helper_heal' \
  'PROPOSE kind=helper tag=helper_drop' \
  'PROPOSE kind=helper tag=helper_keep' \
  'PAD_M3_OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m3: missing: $want" >&2; fail=1; }
done
grep -E -q 'WORLD line=(host-sequential|fiber_live)' "$T" || fail=1
if grep -q 'WORLD line=fiber_live' "$T"; then
  python3 - "$T" << 'PY' || fail=1
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"WORLD line=fiber_live backend=(\d+) joins=(\d+)/(\d+)", text)
if not m or m.group(2) != m.group(3) or int(m.group(1)) <= 0 or int(m.group(2)) <= 0:
    sys.exit(1)
PY
fi
if grep -q '_FAIL\|WANT=' "$T"; then fail=1; fi
if grep -qiE 'error:|unbound variable' "$T" "$ROOT/out/m3_smoke.err"; then fail=1; fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m3: PAD_M3_OK checks failed" >&2
  exit 1
fi
echo "smoke_m3: PAD_M3_OK"

if [[ "${PAD_LIVE:-1}" != "1" ]]; then
  echo "PAD_M3_LIVE_SKIP reason=PAD_LIVE=0"
  exit 0
fi
if ! python3 "$ROOT/scripts/propose_minimax.py" --check 2>/dev/null; then
  echo "PAD_M3_LIVE_SKIP reason=no-key"
  exit 0
fi
echo "smoke: m3 live MiniMax helper propose"
live="$ROOT/out/live_helper.lambda"
rm -f "$live"
if ! python3 "$ROOT/scripts/propose_minimax.py" --helper "$live" 1 "m3 smoke" \
    >/dev/null 2>"$ROOT/out/m3_live_propose.stderr"; then
  cat "$ROOT/out/m3_live_propose.stderr" >&2 || true
  echo "PAD_M3_LIVE_FAIL (host propose)" >&2
  exit 1
fi
cat "$ROOT/out/m3_live_propose.stderr" >&2 || true
test -s "$live"
echo "LIVE_HELPER $(head -c 300 "$live" | tr -d '\n')"
PAD_PROPOSE_FILE="/workspace/aura-pad/out/live_helper.lambda" \
  bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m3_live.aura \
  >"$ROOT/out/m3_live.txt" 2>"$ROOT/out/m3_live.err"
cat "$ROOT/out/m3_live.txt"
if [[ -s "$ROOT/out/m3_live.err" ]]; then
  cat "$ROOT/out/m3_live.err" >&2
fi
if ! grep -q 'PAD_M3_LIVE_OK' "$ROOT/out/m3_live.txt" \
   || grep -qiE 'error:|unbound variable' "$ROOT/out/m3_live.txt" "$ROOT/out/m3_live.err"; then
  echo "PAD_M3_LIVE_FAIL" >&2
  exit 1
fi
echo "PAD_M3_LIVE_OK"
