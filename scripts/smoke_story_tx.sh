#!/usr/bin/env bash
# Step 52. KEEP changes one story sentence. Undo puts the bytes and
# the authors back. Drop changes nothing. Does not call docker.
# Prints PAD_STORY_TX_OK.
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
  echo "smoke_story_tx: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/story-tx"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/story_proj.aura" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/story_tx_test.aura"

fail() { echo "smoke_story_tx: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
sp = (root / "soft/pad/story_proj.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/story_tx_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in sp or banned in test:
        sys.exit("smoke_story_tx: banned word")
def body(src, name):
    a = src.find("(define (" + name)
    if a < 0:
        return ""
    b = src.find("\n(define ", a + 1)
    return src[a:] if b < 0 else src[a:b]
kept = body(tx, "pad:tx-story-kept!")
undo = body(tx, "pad:tx-story-undo!")
if "pad:sp-keep!" not in kept or "pad:sp-undo!" not in undo:
    sys.exit("smoke_story_tx: the card does not use the story record")
for banned in ("set-code", "ast:snapshot", "pad:proj-splice", "pad:play-snap"):
    if banned in kept or banned in undo or banned in sp[sp.find("(define (pad:sp-keep!"):]:
        sys.exit("smoke_story_tx: story keep draws or snapshots")
old = body(tx, "pad:tx-undo!")
if "ast:restore" not in old or "pad:tx-story-undo!" not in old:
    sys.exit("smoke_story_tx: undo lost the old heal or the story record")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/story_tx_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

python3 - "$OUT/unit.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
for need in (
    "CHECK before-bytes=same",
    "CHECK before-who=nobody.nobody.nobody",
    "CHECK drop-say=did drop",
    "CHECK drop-bytes=same",
    "CHECK drop-who=nobody.nobody.nobody",
    "CHECK keep-say=kept",
    "CHECK keep-bytes=same",
    "CHECK keep-who=nobody.nobody.helper",
    "CHECK shown=sentences",
    "CHECK undo-say=undid one keep",
    "CHECK undo-bytes=same",
    "CHECK undo-who=nobody.nobody.nobody",
):
    if need not in lines:
        sys.exit("smoke_story_tx: missing " + need + "\n" + "\n".join(lines))
PY

echo PAD_STORY_TX_OK
