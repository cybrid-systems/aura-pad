#!/usr/bin/env bash
# Step 51. Story refusals are at most eight words.
# An aura page may keep the engine text. Does not call docker.
# Prints PAD_STORY_WHY_OK.
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
  echo "smoke_story_why: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/story-why"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/why.aura" \
  "$ROOT/soft/pad/story_proj.aura" \
  "$ROOT/soft/pad/story_why_test.aura"

fail() { echo "smoke_story_why: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
why = (root / "soft/pad/why.aura").read_text(encoding="utf-8")
sp = (root / "soft/pad/story_proj.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/story_why_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in why or banned in sp or banned in test:
        sys.exit("smoke_story_why: banned word")
if "pad:why-face" not in why or "pad:sp-say!" not in sp:
    sys.exit("smoke_story_why: the story table is missing")
if "pad:play-snap" in sp:
    sys.exit("smoke_story_why: the story program is drawn")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/story_why_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
    <(grep -v '^CHECK type-aura=' "$OUT/unit.txt") "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

python3 - "$OUT/unit.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
need = {
    "CHECK type-story=used a number where words go": "type-story",
    "CHECK type-aura=type error: argument 1: expected String, got Int": "type-aura",
    "CHECK arity-story=hello wants 1 thing, got 2": "arity-story",
    "CHECK arity-aura=arity mismatch: call 'hello': expected 1 arguments, got 2": "arity-aura",
    "CHECK mean-tag=not-kind": "mean-tag",
    "CHECK mean-story=let's use kind words": "mean-story",
    "CHECK mean-aura=let's use kind words": "mean-aura",
    "CHECK ban-tag=not-allowed": "ban-tag",
    "CHECK ban-story=uses a word the pad keeps locked": "ban-story",
    "CHECK ban-aura=that change uses a word the pad keeps locked": "ban-aura",
    "CHECK slot=yes": "slot",
}
got = {k: ln.split("=", 1)[1] for ln in lines if ln.startswith("CHECK ")
       for k in [ln.split("=", 1)[0][6:]]}
missing = [k for k in need if k not in lines]
if missing:
    sys.exit("smoke_story_why: missing " + missing[0] + "\n" + "\n".join(lines))
story_keys = ("type-story", "arity-story", "mean-story", "ban-story")
for key in story_keys:
    text = got[key]
    words = [w for w in text.split(" ") if w]
    if len(words) > 8:
        sys.exit("smoke_story_why: " + key + " has " + str(len(words)) + " words")
    if "type error" in text:
        sys.exit("smoke_story_why: " + key + " shows the engine type line")
if "type error" not in got["type-aura"]:
    sys.exit("smoke_story_why: the aura page lost the engine text")
ban_words = [w for w in got["ban-aura"].split(" ") if w]
if len(ban_words) <= 8:
    sys.exit("smoke_story_why: the aura ban line was shortened")
PY

echo PAD_STORY_WHY_OK
