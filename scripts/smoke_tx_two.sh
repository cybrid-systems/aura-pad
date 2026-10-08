#!/usr/bin/env bash
# Step 43. One sentence asks for two proposals.
# The fixture has no network. This path uses 2, not 3.
# Does not call docker. Does not change *world-max*.
# Prints PAD_TX_TWO_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/tx-two"
rm -rf "$OUT"
mkdir -p "$OUT"
PY="$ROOT/scripts/propose_tx.py"
FIX="$ROOT/soft/pad/fixtures/propose_two.txt"

fail() { echo "smoke_tx_two: $*" >&2; exit 1; }

python3 - "$PY" "$ROOT/soft/pad/world.aura" "$FIX" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
world = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
fix = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
if "TWO_COUNT = 2" not in src or "propose_two.txt" not in src:
    sys.exit("smoke_tx_two: proposer is not fixed at two")
if "urlopen" in src or "http-post" in src or "socket" in src:
    sys.exit("smoke_tx_two: proposer posts")
if "(define *world-max* 3)" not in world:
    sys.exit("smoke_tx_two: world cap changed")
low = fix.lower()
for banned in ("http", "socket", "urlopen", "https"):
    if banned in low:
        sys.exit("smoke_tx_two: fixture has network text " + banned)
PY

env PAD_LIVE=0 python3 "$PY" --two "make hello closer" >"$OUT/two.txt" 2>"$OUT/two.err" \
  || fail "two-proposal run failed"
cmp -s "$OUT/two.txt" "$FIX" || fail "two fixture drifted"

env PAD_LIVE=0 python3 "$PY" --count 2 >"$OUT/count.txt" 2>"$OUT/count.err" \
  || fail "count 2 failed"
cmp -s "$OUT/count.txt" "$FIX" || fail "count 2 drifted"

env PAD_LIVE=0 python3 "$PY" --two >"$OUT/empty.txt" 2>"$OUT/empty.err" \
  && fail "empty sentence was accepted"
if [[ -s "$OUT/empty.txt" ]]; then
  fail "empty sentence wrote stdout"
fi
grep -q "PROPOSE_FAIL sentence" "$OUT/empty.err" || fail "empty sentence was quiet"

env PAD_LIVE=0 python3 "$PY" --count 3 >"$OUT/three.txt" 2>"$OUT/three.err" \
  && fail "a third proposal was accepted"
if [[ -s "$OUT/three.txt" ]]; then
  fail "a third proposal wrote stdout"
fi
grep -q "PROPOSE_FAIL count" "$OUT/three.err" || fail "count 3 was quiet"

env PAD_LIVE=0 python3 "$PY" >"$OUT/one.txt" 2>"$OUT/one.err" \
  || fail "default fixture failed"
cmp -s "$OUT/one.txt" "$ROOT/soft/pad/fixtures/propose_ok.txt" \
  || fail "default fixture drifted"

python3 - "$OUT/two.txt" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
blocks = [b.strip("\n") for b in text.split("\n---\n")]
if len(blocks) != 2:
    sys.exit("smoke_tx_two: block count " + str(len(blocks)))
seen = []
for i, block in enumerate(blocks):
    lines = [ln for ln in block.splitlines() if ln.strip()]
    ops = [ln for ln in lines if "=(lambda " in ln]
    checks = [ln for ln in lines if ln.startswith("check ")]
    if len(ops) < 1 or len(checks) < 1:
        sys.exit("smoke_tx_two: block " + str(i) + " missing op or check")
    if len(ops) > 4:
        sys.exit("smoke_tx_two: block " + str(i) + " has more than 4 ops")
    if "---" in block:
        sys.exit("smoke_tx_two: nested separator")
    seen.append(ops[0])
if seen[0] == seen[1]:
    sys.exit("smoke_tx_two: the two ideas are the same op")
PY

sentinel="SENTINEL_KEY_do_not_leak_two"
home="$OUT/home"
mkdir -p "$home/code/keys"
printf '%s\n' "$sentinel" >"$home/code/keys/deepseek"
env HOME="$home" DEEPSEEK_API_KEY="$sentinel" PAD_LIVE=1 \
  python3 "$PY" --two "make hello closer" >"$OUT/live.txt" 2>"$OUT/live.err" \
  && fail "live should not post"
if grep -q "$sentinel" "$OUT/live.txt" "$OUT/live.err"; then
  fail "key reached the two-proposal output"
fi
if [[ -s "$OUT/live.txt" ]]; then
  fail "live wrote a proposal"
fi
grep -q "model=deepseek-flash" "$OUT/live.err" || fail "live model was not deepseek-flash"

echo PAD_TX_TWO_OK
