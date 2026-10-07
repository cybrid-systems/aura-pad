#!/usr/bin/env bash
# Step 2. PAD_SENTENCE=1 draws the sentence line on a file frame.
# The flag off keeps [normal], and a no-file frame keeps its legend and SAY.
# Prints PAD_UX_CHROME_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA="${AURA_BIN:-}"
if [[ -z "$AURA" || ! -x "$AURA" ]]; then
  for c in /workspace/aura-grok/build/aura \
           "$HOME/code/grok-dev/aura-grok/build/aura" \
           /home/dev/code/grok-dev/aura-grok/build/aura; do
    if [[ -x "$c" ]]; then AURA="$c"; break; fi
  done
fi
if [[ -z "${AURA:-}" || ! -x "$AURA" ]]; then
  echo "ux_chrome: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/ux-chrome"
rm -rf "$OUT"
mkdir -p "$OUT"
printf '(define (hello x) (+ x 1))\n' >"$OUT/hello.aura"
printf 'once upon a time\n' >"$OUT/note.story"

run_play() {
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/play.aura"
}

fail() { echo "ux_chrome: $*" >&2; exit 1; }

printf 'QUIT\n' | run_play >"$OUT/bare.txt" 2>"$OUT/bare.err" || { cat "$OUT/bare.err" >&2; exit 1; }
printf 'QUIT\n' | PAD_SENTENCE=1 run_play >"$OUT/bare-ux.txt" 2>"$OUT/bare-ux.err" \
  || { cat "$OUT/bare-ux.err" >&2; exit 1; }
cmp -s "$OUT/bare.txt" "$OUT/bare-ux.txt" || fail "no-file frame changed"

printf 'QUIT\n' | PAD_VI=1 PAD_FILE="$OUT/hello.aura" run_play >"$OUT/vi.txt" 2>"$OUT/vi.err" \
  || { cat "$OUT/vi.err" >&2; exit 1; }
grep -q '\[normal\]' "$OUT/vi.txt" || fail "file frame lost [normal]"
grep -q '^LEGEND > ' "$OUT/vi.txt" && fail "flag off drew the sentence line"

printf 'QUIT\n' | PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/ux.txt" 2>"$OUT/ux.err" || { cat "$OUT/ux.err" >&2; exit 1; }
grep -q '^LEGEND > $' "$OUT/ux.txt" || fail "legend is not the empty sentence line"
grep -q 'hello\.aura  aura  new' "$OUT/ux.txt" || fail "title missing name or new"
if grep -q '\[normal\]\|\[insert\]' "$OUT/ux.txt"; then
  fail "sentence title still has a vi mode"
fi
grep -q '^SAY not checked yet$' "$OUT/ux.txt" || fail "file SAY is not one sentence"

printf 'QUIT\n' | PAD_SENTENCE=1 PAD_FILE="$OUT/note.story" \
  run_play >"$OUT/story.txt" 2>"$OUT/story.err" || { cat "$OUT/story.err" >&2; exit 1; }
grep -q 'note\.story  story  new' "$OUT/story.txt" || fail "story title"
grep -q '^LEGEND > $' "$OUT/story.txt" || fail "story legend"

if grep -qiE 'error:|unbound variable' \
     "$OUT/bare.txt" "$OUT/bare.err" "$OUT/bare-ux.txt" "$OUT/bare-ux.err" \
     "$OUT/vi.txt" "$OUT/vi.err" "$OUT/ux.txt" "$OUT/ux.err" \
     "$OUT/story.txt" "$OUT/story.err"; then
  fail "Soft error"
fi
echo PAD_UX_CHROME_OK
