#!/usr/bin/env bash
# Step 56. The first idea fails a type check. The second passes.
# SAY has try 1 and try 2, matching intend-history. The page changes
# on the final KEEP. The verifier is the child world. Does not call docker.
# Prints PAD_TX_FIX_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA="${AURA_BIN:-}"
if [[ -z "$AURA" || ! -x "$AURA" ]]; then
  for c in /workspace/aura-grok/build-release/aura \
           "$HOME/code/grok-dev/aura-grok/build-release/aura" \
           /home/dev/code/grok-dev/aura-grok/build-release/aura \
           /workspace/aura-grok/build/aura \
           "$HOME/code/grok-dev/aura-grok/build/aura" \
           /home/dev/code/grok-dev/aura-grok/build/aura; do
    if [[ -x "$c" ]]; then AURA="$c"; break; fi
  done
fi
if [[ -z "${AURA:-}" || ! -x "$AURA" ]]; then
  echo "smoke_tx_fix: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/tx-fix"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "smoke_tx_fix: $*" >&2; exit 1; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx_fix_test.aura" \
  "$ROOT/soft/pad/fix_loop.aura" \
  "$ROOT/soft/pad/tx.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
fx = (root / "soft/pad/fix_loop.aura").read_text(encoding="utf-8")
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/tx_fix_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in fx or banned in test:
        sys.exit("smoke_tx_fix: banned word")
if "(define *fx-max* 3)" not in fx:
    sys.exit("smoke_tx_fix: repair cap moved")
a = fx.find("(define (pad:fx-verify ")
b = fx.find("\n(define ", a + 1)
if a < 0 or b < 0:
    sys.exit("smoke_tx_fix: missing the verifier")
body = fx[a:b]
if "pad:world-run1" not in body:
    sys.exit("smoke_tx_fix: verifier is not the child world")
if "(eval " in body:
    sys.exit("smoke_tx_fix: verifier evals")
c = tx.find("(define (pad:tx-fix! ")
d = tx.find("\n(define ", c + 1)
if c < 0:
    sys.exit("smoke_tx_fix: missing the sentence repair")
fixfn = tx[c:] if d < 0 else tx[c:d]
if "pad:fx-tx!" not in fixfn:
    sys.exit("smoke_tx_fix: sentence repair does not use the intend entry")
if "(eval " in fixfn:
    sys.exit("smoke_tx_fix: sentence repair evals")
for rel in ("soft/pad/play.aura", "soft/pad/ux.aura"):
    text = (root / rel).read_text(encoding="utf-8")
    if "fix_loop.aura" in text:
        sys.exit("smoke_tx_fix: " + rel + " loads the repair file")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/tx_fix_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak|M11_FIX_DISAGREE' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi
for line in \
  "CHECK load=ok" \
  "CHECK tag=ok" \
  "CHECK verdict=ok" \
  "CHECK say-1=ok" \
  "CHECK say-2=ok" \
  "CHECK say-line=ok" \
  "CHECK hist-1=ok" \
  "CHECK hist-2=ok" \
  "CHECK disagree=ok" \
  "CHECK tries=ok" \
  "CHECK type=ok" \
  "CHECK during=ok" \
  "CHECK moved=ok" \
  "CHECK kept=ok" \
  "CHECK no-bad=ok" \
  "CHECK row1=ok" \
  "CHECK hello=ok" \
  "CHECK bye=ok" \
  "CHECK kids=ok" \
  "CHECK max=ok" \
  "TX_FIX_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
echo "PAD_TX_FIX_OK"
