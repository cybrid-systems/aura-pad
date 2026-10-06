#!/usr/bin/env bash
# M10: who wrote this (who.aura) + pen stamps / engine dirty cross-check
# (who_pen.aura) on Soft tip.
#   1. paren balance of who/who_pen/m10_* + play.aura           -> PAREN_OK
#   2. Soft tests (m10_test.aura -> m10_cases.aura)             -> PAD_M10_TEST_OK
#      four ROADMAP acceptance items                            -> M10_ACC 1..4 OK
#   3. play stream: ctrl-o (IN 15) answers in SAY through play.aura
#   4. markers                                                  -> PAD_M10_OK
# Typing stays on the M7 key path: stamps sync only at ctrl-o and pen steps.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out/m10"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/who.aura "$ROOT"/soft/pad/who_pen.aura \
  "$ROOT"/soft/pad/m10_test.aura "$ROOT"/soft/pad/m10_cases.aura \
  "$ROOT"/soft/pad/play.aura

echo "smoke_m10: Soft tests"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m10_test.aura \
  </dev/null >"$ROOT/out/m10/m10_test.txt" 2>"$ROOT/out/m10/m10_test.err"
T="$ROOT/out/m10/m10_test.txt"
grep -E '^(M10_ACC|M10STATS|XDIRTY|GAPS|WHO |no-who|TESTS|PAD_M10_TEST)' "$T" || true
if ! grep -q '^PAD_M10_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m10/m10_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m10/m10_test.err" >&2 || true
  echo "smoke_m10: PAD_M10_TEST_FAIL" >&2
  exit 1
fi
if [[ "$(grep -c '^M10 who wrote this on Soft tip$' "$T")" -ne 1 ]]; then
  echo "smoke_m10: test file ran more than once" >&2; exit 1
fi
checks=$(sed -n 's/^TESTS checks=\([0-9]*\) fail=0$/\1/p' "$T")
if [[ -z "$checks" || "$checks" -lt 50 ]]; then
  echo "smoke_m10: too few checks (${checks:-none})" >&2; exit 1
fi
echo "smoke_m10: PAD_M10_TEST_OK checks=$checks"

fail=0
for n in 1 2 3 4; do
  grep -qx "M10_ACC $n OK" "$T" || { echo "smoke_m10: missing: M10_ACC $n OK" >&2; fail=1; }
done
for want in \
  'T DIRTY_NODES_BOUND=yes OK' \
  'no-who row=3 say="nobody has changed this yet"' \
  'WHO who=kid why=typed gen=' \
  'WHO who=macro why=swap gen=' \
  'WHO who=law why=commutes gen=' \
  'T UNDO_STAMP=WHO who=helper why=closer gen=' \
  'T K3_UNDO=agree OK' \
  'T K3_PLANTED=disagree OK' \
  'XDIRTY at=keep-hello verdict=ok engine=0 ' \
  'XDIRTY at=keep-add verdict=ok engine=2 soft=2.5 cursor=5 ' \
  'T GAP_PATH=gap OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m10: missing: $want" >&2; fail=1; }
done
grep -qE '^WHO who=helper why=closer gen=[0-9]+ row=0 say="the AI helper wrote this line: closer"$' "$T" \
  || { echo "smoke_m10: missing: WHO who=helper why=closer" >&2; fail=1; }
# the only disagreement is the planted one; the only GAPS dirty-nodes line
# is the simulated unbound path; no real cross-check may miss
[[ "$(grep -c '^M10_UNDO_DISAGREE' "$T")" -eq 1 ]] \
  && grep -q '^M10_UNDO_DISAGREE page=yes code=no gen=yes proj=yes$' "$T" \
  || { echo "smoke_m10: undo disagreement count/shape" >&2; fail=1; }
[[ "$(grep -c '^GAPS query:dirty-nodes$' "$T")" -eq 1 ]] \
  || { echo "smoke_m10: GAPS query:dirty-nodes outside the simulated path" >&2; fail=1; }
if grep -q '^XDIRTY .*verdict=miss' "$T"; then
  echo "smoke_m10: engine dirty row outside Soft DIRTY + cursor" >&2; fail=1
fi

echo "smoke_m10: play stream ctrl-o"
P="$ROOT/out/m10/play_who.txt"
printf 'IN 15\nIN 97\nIN 15\nKEY undo\nIN 15\nQUIT\n' \
  | bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/play.aura \
  >"$P" 2>"$ROOT/out/m10/play_who.err"
got=$(grep '^SAY ' "$P" | sed -n '2p;4p;6p' | tr '\n' '|')
want='SAY nobody has changed this yet|SAY you wrote this line|SAY nobody has changed this yet|'
if [[ "$got" != "$want" ]] || soft_errs "$P" "$ROOT/out/m10/play_who.err"; then
  echo "smoke_m10: play ctrl-o SAY got=$got" >&2; fail=1
else
  echo "smoke_m10: PLAY_WHO_OK"
fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m10: PAD_M10_OK checks failed" >&2
  exit 1
fi
grep -E '^M10STATS ' "$T"
echo "smoke_m10: PAD_M10_OK"
