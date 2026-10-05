#!/usr/bin/env bash
# M2 fixture propose. No MiniMax, no HTTP. → PAD_M2_PROPOSE_OK
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"
echo "smoke: m2 fixture"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m2_propose_smoke.aura \
  >"$ROOT/out/m2_propose.txt" 2>"$ROOT/out/m2_propose.err"
cat "$ROOT/out/m2_propose.txt"
if [[ -s "$ROOT/out/m2_propose.err" ]]; then
  cat "$ROOT/out/m2_propose.err" >&2
fi
T="$ROOT/out/m2_propose.txt"
fail=0
grep -q 'GATE reject reason=gate word=set!' "$T" || fail=1
grep -q 'GATE reject reason=gate word=display' "$T" || fail=1
grep -q 'PROPOSE tag=propose_reject' "$T" || fail=1
grep -q 'PROPOSE tag=propose_heal' "$T" || fail=1
grep -q 'PROPOSE tag=propose_drop' "$T" || fail=1
grep -q 'PROPOSE tag=propose_keep' "$T" || fail=1
grep -q 'RACE base=9 trial=-2' "$T" || fail=1
grep -q 'RACE base=9 trial=10' "$T" || fail=1
grep -q 'KEEP reason=higher-score-stamp score=10' "$T" || fail=1
grep -q 'DROP reason=lower-score-rollback score=-2' "$T" || fail=1
grep -q 'PAD_M2_PROPOSE_OK' "$T" || fail=1
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
if grep -q '_FAIL\|WANT=' "$T"; then
  fail=1
fi
if grep -qiE 'error:|unbound variable' "$T" "$ROOT/out/m2_propose.err"; then
  fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m2: PAD_M2_PROPOSE_OK checks failed" >&2
  exit 1
fi
echo "smoke_m2: PAD_M2_PROPOSE_OK"
