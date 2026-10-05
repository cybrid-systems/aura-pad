#!/usr/bin/env bash
# Multi-round propose -> gate -> play. Default 3 rounds, 24 keys.
# PAD_PROPOSE=1 calls MiniMax per round when a key is configured; else fixtures.
# PAD_PROPOSE=0 always uses soft/pad/fixtures/burn (offline). → PAD_BURN_OK
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PAD_BURN_ROUNDS="${PAD_BURN_ROUNDS:-3}"
export PAD_HORIZON="${PAD_HORIZON:-24}"
PAD_PROPOSE="${PAD_PROPOSE:-1}"
mkdir -p "$ROOT/out"
mode="fixture"
if [[ "$PAD_PROPOSE" == "1" ]] && python3 "$ROOT/scripts/propose_minimax.py" --check 2>/dev/null; then
  mode="live"
fi

if [[ "$mode" == "live" ]]; then
  dir="$ROOT/out/burn-rounds"
  rm -rf "$dir"
  mkdir -p "$dir"
  prev=""
  note="main is (list 3 20 0) scoring 9"
  for ((r=1; r<=PAD_BURN_ROUNDS; r++)); do
    out="$dir/${r}.lambda"
    echo "burn: propose round ${r}"
    python3 "$ROOT/scripts/propose_minimax.py" "$out" "$r" "$note" ${prev:+"$prev"} \
      >/dev/null 2>"$ROOT/out/burn_propose_${r}.stderr" || true
    cat "$ROOT/out/burn_propose_${r}.stderr" >&2 || true
    if [[ ! -s "$out" ]]; then
      # Honest: a failed proposal still goes to Soft as an empty body → GATE reject.
      echo "(none)" >"$out"
    fi
    echo "burn: round ${r} $(tr -d '\n' < "$out")"
    prev="$out"
    note="round ${r} proposed $(tr -d '\n' < "$out")"
  done
  export PAD_ROUND_DIR="/workspace/aura-pad/out/burn-rounds"
else
  echo "burn: fixture rounds"
  export PAD_ROUND_DIR="/workspace/aura-pad/soft/pad/fixtures/burn"
fi

echo "burn: mode=${mode} rounds=${PAD_BURN_ROUNDS} keys=${PAD_HORIZON} dir=${PAD_ROUND_DIR}"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/burn.aura \
  >"$ROOT/out/burn.txt" 2>"$ROOT/out/burn.err"
cat "$ROOT/out/burn.txt"
if [[ -s "$ROOT/out/burn.err" ]]; then
  cat "$ROOT/out/burn.err" >&2
fi
T="$ROOT/out/burn.txt"
fail=0
grep -q 'PAD_BURN_OK' "$T" || fail=1
grep -E -q 'WORLD line=(host-sequential|fiber_live)' "$T" || fail=1
if [[ "$mode" == "fixture" ]]; then
  grep -q 'RACE base=9 trial=10' "$T" || fail=1
  grep -q 'KEEP reason=higher-score-stamp score=10' "$T" || fail=1
  grep -q 'DROP reason=tie-is-not-better-rollback score=10' "$T" || fail=1
  grep -q 'DROP reason=lower-score-rollback score=-2' "$T" || fail=1
  grep -q 'MAIN score=10 ' "$T" || fail=1
fi
if grep -q '_FAIL' "$T"; then fail=1; fi
if grep -qiE 'error:|unbound variable' "$T" "$ROOT/out/burn.err"; then fail=1; fi
if [[ "$fail" -ne 0 ]]; then
  echo "burn: PAD_BURN_OK checks failed" >&2
  exit 1
fi
echo "burn: PAD_BURN_OK mode=${mode}"
