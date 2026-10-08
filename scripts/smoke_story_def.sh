#!/usr/bin/env bash
# Step 50. A three-line story is s1 s2 s3 in the child.
# The projection stays the sentences. Does not call docker.
# Prints PAD_STORY_DEF_OK.
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
  echo "smoke_story_def: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/story-def"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/story_proj.aura" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/story_def_test.aura"

fail() { echo "smoke_story_def: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
sp = (root / "soft/pad/story_proj.aura").read_text(encoding="utf-8")
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/story_def_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in sp or banned in test:
        sys.exit("smoke_story_def: banned word")
if "query:defines" not in sp or "pad:tx-gate" not in sp:
    sys.exit("smoke_story_def: the child does not ask the engine")
if "pad:play-snap" in sp:
    sys.exit("smoke_story_def: the story program is drawn")
a = tx.find("(define (pad:tx-story-child! ")
if a < 0:
    sys.exit("smoke_story_def: missing the child entry")
b = tx.find("\n(define ", a + 1)
body = tx[a:] if b < 0 else tx[a:b]
if "set-code" in body or "pad:play-snap" in body:
    sys.exit("smoke_story_def: the entry writes the screen")
if "pad:sp-child!" not in body:
    sys.exit("smoke_story_def: the entry does not build the child")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/story_def_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

python3 - "$OUT/unit.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
for need in ("CHECK names=s1.s2.s3", "CHECK before=no-def", "CHECK gate=ok",
             "CHECK wrote=yes", "CHECK page=same", "CHECK shown=sentences",
             "CHECK code=not aura code", "CHECK story=not a story"):
    if need not in lines:
        sys.exit("smoke_story_def: missing " + need + "\n" + "\n".join(lines))
PY

echo PAD_STORY_DEF_OK
