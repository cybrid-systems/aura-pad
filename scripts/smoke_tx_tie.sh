#!/usr/bin/env bash
# Step 46. A tie drops both ideas. Does not call docker.
# Prints PAD_TX_TIE_OK.
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
  echo "smoke_tx_tie: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/tx-tie"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/tie_tx_test.aura"

fail() { echo "smoke_tx_tie: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/tie_tx_test.aura").read_text(encoding="utf-8")
fix = (root / "soft/pad/fixtures/propose_tie.txt").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test or banned in fix:
        sys.exit("smoke_tx_tie: banned word")
parts = fix.split("\n---\n")
if len(parts) != 2 or parts[0] == parts[1]:
    sys.exit("smoke_tx_tie: fixture is not two different ideas")
for part in parts:
    if "=(lambda " not in part or "check " not in part:
        sys.exit("smoke_tx_tie: idea missing an op or a check")
a = tx.find("(define (pad:tx-tie-text! ")
b = tx.find("\n(define (pad:tx-tie!)", a)
if a < 0 or b < 0:
    sys.exit("smoke_tx_tie: missing the tie")
body = tx[a:b]
if "pad:tx-world-race!" not in body or "(= (car host) (cadr host))" not in body:
    sys.exit("smoke_tx_tie: tie does not compare the two host scores")
for banned in ("pad:tx-card-keep!", "pad:tx-card-splice!", "pad:proj-splice",
               "pad:tx-card-show!", "set-code", "ast:snapshot",
               "string-split", "string-trim", "string-replace"):
    if banned in body:
        sys.exit("smoke_tx_tie: tie writes " + banned)
if "neither is better" not in body:
    sys.exit("smoke_tx_tie: missing the sentence")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  TIE_BEFORE="$OUT/before" TIE_AFTER="$OUT/after" \
  "$AURA" "$ROOT/soft/pad/tie_tx_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

cmp -s "$OUT/before" "$OUT/after" || fail "tie changed the projection"
if [[ ! -s "$OUT/before" ]]; then
  fail "empty projection"
fi

python3 - "$OUT/unit.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
say = [ln for ln in lines if ln.startswith("CHECK say=")]
if say != ["CHECK say=neither is better"]:
    sys.exit("smoke_tx_tie: say " + repr(say))
text = say[0][len("CHECK say="):]
for banned in ("keep", "drop", "undo", "press", "help", "M-x",
               "finish this card", "> "):
    if banned in text:
        sys.exit("smoke_tx_tie: command help in SAY: " + banned)
for need in ("CHECK page=same", "CHECK old=yes", "CHECK form-a=no",
             "CHECK form-b=no", "SCORE a=1", "SCORE b=1", "TIE score=1"):
    if need not in lines:
        sys.exit("smoke_tx_tie: missing " + need)
if any(ln.startswith("CARD keep=") for ln in lines):
    sys.exit("smoke_tx_tie: a tie wrote")
PY

echo PAD_TX_TIE_OK
