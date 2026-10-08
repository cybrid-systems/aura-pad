#!/usr/bin/env bash
# Step 49. A story or text file opens as sentences.
# TITLE says story. An aura file says aura, and its sexp row stays.
# Does not call docker. Prints PAD_STORY_OPEN_OK.
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
  echo "smoke_story_open: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/story-open"
rm -rf "$OUT"
mkdir -p "$OUT"
printf 'once upon a time\n' >"$OUT/note.story"
printf 'the cat sat\n' >"$OUT/note.txt"
printf '(define (hello x) (+ x 1))\n' >"$OUT/hello.aura"

fail() { echo "smoke_story_open: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
kind = ux[ux.find("(define (pad:ux-kind "):ux.find("(define (pad:ux-chrome!")]
if ".story" not in kind or ".txt" not in kind or '"story"' not in kind:
    sys.exit("smoke_story_open: story and text are not one kind")
if '"aura"' not in kind:
    sys.exit("smoke_story_open: an aura file has no aura title")
hl = (root / "soft/pad/hl.aura").read_text(encoding="utf-8")
# The sexp highlighter stays the aura path. This step does not rewrite it.
if "(define (pad:hl-tokens " not in hl:
    sys.exit("smoke_story_open: sexp highlight moved")
PY

run_play() {
  local dest="$1"
  shift
  env -u PAD_CLASSIC "$@" \
    AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 PAD_SENTENCE=1 \
    "$AURA" "$ROOT/soft/pad/play.aura" >"$dest" 2>"$dest.err" \
    || { cat "$dest.err" >&2; exit 1; }
  if grep -qiE 'error:|unbound variable' "$dest" "$dest.err"; then
    cat "$dest" "$dest.err" >&2
    fail "soft error in $dest"
  fi
}

printf 'QUIT\n' | run_play "$OUT/story.snap" PAD_FILE="$OUT/note.story"
printf 'QUIT\n' | run_play "$OUT/txt.snap" PAD_FILE="$OUT/note.txt"
printf 'QUIT\n' | run_play "$OUT/aura.snap" PAD_FILE="$OUT/hello.aura"

python3 - "$OUT/story.snap" "$OUT/txt.snap" "$OUT/aura.snap" <<'PY'
import sys
story, txt, aura = [open(p, encoding="utf-8").read().splitlines() for p in sys.argv[1:]]

def title(lines):
    hit = [ln for ln in lines if ln.startswith("TITLE ")]
    if len(hit) != 1:
        sys.exit("smoke_story_open: title lines " + str(hit))
    return hit[0]

def rows(lines):
    return [ln for ln in lines if ln.startswith("T ")]

st, tt, at = title(story), title(txt), title(aura)
if " story " not in st:
    sys.exit("smoke_story_open: story title " + st)
if " story " not in tt:
    sys.exit("smoke_story_open: text title " + tt)
if " aura " not in at:
    sys.exit("smoke_story_open: aura title " + at)
if " story " in at:
    sys.exit("smoke_story_open: aura title says story")
sr, tr = rows(story), rows(txt)
if sr != ["T once upon a time"] or tr != ["T the cat sat"]:
    sys.exit("smoke_story_open: projection " + repr(sr) + " " + repr(tr))
for ln in sr + tr:
    if "(define" in ln:
        sys.exit("smoke_story_open: sentence row shows a define")
ar = rows(aura)
if not any("(define (hello x)" in ln for ln in ar):
    sys.exit("smoke_story_open: aura sexp row changed " + repr(ar))
PY

echo PAD_STORY_OPEN_OK
