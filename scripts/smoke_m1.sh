#!/usr/bin/env bash
# M1 hot keymap pack swap/heal + honest worldline → PAD_M1_OK. M0 unchanged.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"
echo "smoke: m1"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m1_smoke.aura \
  >"$ROOT/out/m1_smoke.txt" 2>"$ROOT/out/m1_smoke.err"
cat "$ROOT/out/m1_smoke.txt"
if [[ -s "$ROOT/out/m1_smoke.err" ]]; then
  cat "$ROOT/out/m1_smoke.err" >&2
fi
T="$ROOT/out/m1_smoke.txt"
fail=0
grep -q 'SWAP name=pd:law key=10' "$T" || fail=1
grep -q 'HEAL name=pd:law key=15 reason=probe' "$T" || fail=1
grep -q 'MUTATE key=8 room-boost=2' "$T" || fail=1
grep -q 'GATE reject reason=gate word=set!' "$T" || fail=1
grep -q 'REJECT mid=0 reason=too-far' "$T" || fail=1
grep -q 'KEEP mid=' "$T" || fail=1
grep -q 'DROP mid=' "$T" || fail=1
grep -q 'PAD_M1_OK' "$T" || fail=1
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
if grep -q 'PAD_M1_FAIL\|_FAIL\|WANT=' "$T"; then
  fail=1
fi
if grep -qiE 'error:|unbound variable' "$T" "$ROOT/out/m1_smoke.err"; then
  fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m1: PAD_M1_OK checks failed" >&2
  exit 1
fi
echo "smoke_m1: PAD_M1_OK"
