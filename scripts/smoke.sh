#!/usr/bin/env bash
# Full stack: M0 race → M1 hot swap/heal → M2 fixture propose → optional
# live MiniMax propose (PAD_M2_PROPOSE_LIVE_SKIP when no key, or PAD_LIVE=0)
# → fixture burn → M3 multi-line buffer + command-helper propose (fixtures,
# then optional live helper; PAD_M3_LIVE_SKIP when no key or PAD_LIVE=0)
# → M3.5 finer editor (paren check, Python model, Soft unit tests
# PAD_TEST_OK, goal3 helper race + world undo PAD_M35_OK, optional live
# --helper3; PAD_M35_LIVE_SKIP when no key or PAD_LIVE=0)
# → M4 two pads + find/replace + record/play (paren, Python model
# PAD_M4_MODEL_OK, Soft tests PAD_M4_TEST_OK, law race + macro race +
# macro undo PAD_M4_OK, optional live --macro; PAD_M4_LIVE_SKIP when no key
# or PAD_LIVE=0).
# → M5 Soft Aura HL + LSP-lite jump/refs + Soft query/mutate bridge
# (paren, Python model PAD_M5_MODEL_OK, Soft tests PAD_M5_TEST_OK,
# HL/jump/query smoke PAD_M5_OK).
# → M6 thin C viewport (Soft tests PAD_M6_TEST_OK, Soft snapshot PAD_M6_OK,
# host model PAD_M6_MODEL_OK, C thin guard, golden/fail-closed blits,
# soft_play → C blit; PAD_C_OK). Soft owns the editor; C only blits.
# → key-path latency (Soft HL cache + DIRTY; PAD_PERF_OK).
# Ends with PAD_SMOKE_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"

bash "$ROOT/scripts/smoke_soft.sh"
bash "$ROOT/scripts/smoke_m1.sh"
bash "$ROOT/scripts/smoke_m2.sh"

if [[ "${PAD_LIVE:-1}" != "1" ]]; then
  echo "PAD_M2_PROPOSE_LIVE_SKIP reason=PAD_LIVE=0"
elif ! python3 "$ROOT/scripts/propose_minimax.py" --check 2>/dev/null; then
  echo "PAD_M2_PROPOSE_LIVE_SKIP reason=no-key"
else
  echo "smoke: live MiniMax propose"
  live="$ROOT/out/live_pack.lambda"
  rm -f "$live"
  if python3 "$ROOT/scripts/propose_minimax.py" "$live" 1 "smoke" \
      >/dev/null 2>"$ROOT/out/live_propose.stderr"; then
    cat "$ROOT/out/live_propose.stderr" >&2 || true
    test -s "$live"
    echo "LIVE_LAMBDA $(head -c 200 "$live" | tr -d '\n')"
    PAD_PROPOSE_FILE="/workspace/aura-pad/out/live_pack.lambda" \
      bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m2_live.aura \
      >"$ROOT/out/m2_live.txt" 2>"$ROOT/out/m2_live.err"
    cat "$ROOT/out/m2_live.txt"
    if [[ -s "$ROOT/out/m2_live.err" ]]; then
      cat "$ROOT/out/m2_live.err" >&2
    fi
    if ! grep -q 'PAD_M2_PROPOSE_LIVE_OK' "$ROOT/out/m2_live.txt" \
       || grep -qiE 'error:|unbound variable' "$ROOT/out/m2_live.txt" "$ROOT/out/m2_live.err"; then
      echo "PAD_M2_PROPOSE_LIVE_FAIL" >&2
      exit 1
    fi
    echo "PAD_M2_PROPOSE_LIVE_OK"
  else
    cat "$ROOT/out/live_propose.stderr" >&2 || true
    echo "PAD_M2_PROPOSE_LIVE_FAIL (host propose)" >&2
    exit 1
  fi
fi

echo "smoke: fixture burn"
PAD_PROPOSE=0 bash "$ROOT/scripts/burn.sh"

echo "smoke: m3 multi-line + command helper"
bash "$ROOT/scripts/smoke_m3.sh"

echo "smoke: m3.5 finer editor + tests"
bash "$ROOT/scripts/smoke_m35.sh"

echo "smoke: m4 pads + find/replace + macros"
bash "$ROOT/scripts/smoke_m4.sh"

echo "smoke: m5 HL + jump/refs + query/mutate"
bash "$ROOT/scripts/smoke_m5.sh"

echo "smoke: m6 thin C viewport (Soft dump -> C blit)"
bash "$ROOT/scripts/smoke_c.sh"

echo "smoke: key-path latency (Soft cache / DIRTY)"
bash "$ROOT/scripts/smoke_perf.sh"

echo "smoke: PAD_SMOKE_OK"
