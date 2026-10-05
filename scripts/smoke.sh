#!/usr/bin/env bash
# Full stack: M0 race → M1 hot swap/heal → M2 fixture propose → optional
# live MiniMax propose (PAD_M2_PROPOSE_LIVE_SKIP when no key, or PAD_LIVE=0)
# → fixture burn. Ends with PAD_SMOKE_OK.
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

echo "smoke: PAD_SMOKE_OK"
