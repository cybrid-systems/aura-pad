#!/usr/bin/env bash
# Gap round: pty latency per key (docs/perf-emacs.md "Closing the gap").
#   1. paren balance of play_in/play/lc/keys + gap_*            -> PAREN_OK
#   2. Soft tests (gap_test.aura -> gap_cases.aura): flat scanner ==
#      nested scanner, one-entry play-step! frames == reference path,
#      inline fast paths taken; gap2 quote stream: row splice and
#      O(1) memo swaps taken, ROWS == whole-page render; gap3 end-of-row
#      typing: entries built without the scan == a full row scan -> PAD_GAP_TEST_OK
#   3. one "IN b1 .. bn" line per key through play.aura == one "IN b" line
#      per byte (same SNAP stream, byte for byte)                -> GAP_BATCH_OK
#   4. C tty update: pad_view --replay (cell diff, IL/DL) leaves the same
#      screen as --replay-full after every frame (scripts/term_model.py)
#                                                                -> TERM_MODEL_OK
# Ends with PAD_GAP_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/gap"
mkdir -p "$OUT" "$ROOT/out/c"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/play_in.aura "$ROOT"/soft/pad/play.aura \
  "$ROOT"/soft/pad/lc.aura "$ROOT"/soft/pad/keys.aura \
  "$ROOT"/soft/pad/gap_test.aura "$ROOT"/soft/pad/gap_cases.aura

echo "smoke_gap: Soft tests"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/gap_test.aura \
  </dev/null >"$OUT/gap_test.txt" 2>"$OUT/gap_test.err"
T="$OUT/gap_test.txt"
grep -E '^(T |GAPSTATS|GAP2STATS|GAP3STATS|TESTS|PAD_GAP_TEST)' "$T" || true
if ! grep -q '^PAD_GAP_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$OUT/gap_test.err"; then
  cat "$OUT/gap_test.err" >&2 || true
  echo "smoke_gap: PAD_GAP_TEST_FAIL" >&2
  exit 1
fi
if [[ "$(grep -c '^GAP one-entry play path on Soft tip$' "$T")" -ne 1 ]]; then
  echo "smoke_gap: test file ran more than once" >&2; exit 1
fi

echo "smoke_gap: batched lines == byte lines"
python3 - "$OUT" <<'PY'
import random, sys
out = sys.argv[1]
random.seed(11)
setup = ["IN 27", "IN 91", "IN 66"] * 4 + ["IN 5"]
pool = [[97], [98], [100], [101], [113], [58], [49], [32], [59], [92], [34], [40], [41],
        [127], [127], [27, 91, 68], [27, 91, 68], [27, 91, 67], [27, 91, 65], [27, 91, 66],
        [1], [5], [13], [11], [25], [31], [15], [7], [2], [18]]
keys = [random.choice(pool) for _ in range(220)]
single = setup + [f"IN {b}" for k in keys for b in k] + ["KEY goal:hi aura", "QUIT"]
batch = setup + ["IN " + " ".join(map(str, k)) for k in keys] + ["KEY goal:hi aura", "QUIT"]
open(f"{out}/batch_single.in", "w").write("\n".join(single) + "\n")
open(f"{out}/batch_batch.in", "w").write("\n".join(batch) + "\n")
PY
for v in single batch; do
  bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/play.aura \
    <"$OUT/batch_$v.in" >"$OUT/batch_$v.out" 2>"$OUT/batch_$v.err"
  if soft_errs "$OUT/batch_$v.out" "$OUT/batch_$v.err"; then
    cat "$OUT/batch_$v.err" >&2; echo "smoke_gap: play $v errors" >&2; exit 1
  fi
done
frames=$(grep -c '^END$' "$OUT/batch_single.out" || true)
if [[ "$frames" -lt 200 ]] || ! cmp -s "$OUT/batch_single.out" "$OUT/batch_batch.out"; then
  echo "smoke_gap: batched play stream differs (frames=$frames)" >&2; exit 1
fi
echo "smoke_gap: GAP_BATCH_OK frames=$frames"

echo "smoke_gap: C tty update == full repaint"
if command -v cc >/dev/null 2>&1; then
  cc -std=c11 -O2 -Wall -Wextra -pedantic "$ROOT/c/snap.c" "$ROOT/c/pad_view.c" -o "$ROOT/out/c/pad_view_gap"
  V=("$ROOT/out/c/pad_view_gap")
else
  bash "$ROOT/scripts/build_c.sh" >/dev/null
  V=("$ROOT/out/c/pad_view")
fi
"${V[@]}" --replay "$OUT/batch_single.out" >"$OUT/replay_diff.bin"
"${V[@]}" --replay-full "$OUT/batch_single.out" >"$OUT/replay_full.bin"
python3 "$ROOT/scripts/term_model.py" "$OUT/replay_diff.bin" "$OUT/replay_full.bin" | tee "$OUT/term_model.txt"
grep -q '^TERM_MODEL_OK ' "$OUT/term_model.txt" || { echo "smoke_gap: tty update drifted" >&2; exit 1; }
grep -q $'\033\\[L' "$OUT/replay_diff.bin" && grep -q $'\033\\[M' "$OUT/replay_diff.bin" \
  || { echo "smoke_gap: insert/delete line path not exercised" >&2; exit 1; }

echo "smoke_gap: PAD_GAP_OK"
