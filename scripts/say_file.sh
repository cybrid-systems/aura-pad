#!/usr/bin/env bash
# Step 4. save, open, and quit are sentences when PAD_SENTENCE=1.
# They call pad:pf-save!, pad:pf-open!, and pad:pf-quit!.
# They are not added to *em-cmds*. The flag off keeps ctrl-x.
# Prints PAD_SAY_FILE_OK.
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
  echo "say_file: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/say-file"
rm -rf "$OUT"
mkdir -p "$OUT"
printf '(define (hello x) (+ x 1))\n' >"$OUT/hello.aura"
printf '(define (other y) y)\n' >"$OUT/other.aura"
cp "$OUT/hello.aura" "$OUT/hello.orig"
cp "$OUT/other.aura" "$OUT/other.orig"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/ux.aura" "$ROOT/soft/pad/file.aura" "$ROOT/soft/pad/play.aura"

python3 - "$ROOT" <<'PY'
import sys
root = sys.argv[1]
ux = open(root + "/soft/pad/ux.aura", encoding="utf-8").read()
em = open(root + "/soft/pad/emacs.aura", encoding="utf-8").read()
if "*em-cmds*" in ux:
    sys.exit("say_file: sentence words go through *em-cmds*")
cmds = em.split("(define *em-cmds*", 1)[1].split("))", 1)[0]
if '"open"' in cmds:
    sys.exit("say_file: open was added to *em-cmds*")
for name, fn in (
    ("save", "pad:pf-save!"),
    ("open", "pad:pf-open!"),
    ("quit", "pad:pf-quit!"),
):
    body = ux.split("(define (pad:ux-file-" + name, 1)[1].split("\n(define ", 1)[0]
    if fn not in body:
        sys.exit("say_file: " + name + " does not call " + fn)
PY

run_play() {
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/play.aura"
}

fail() { echo "say_file: $*" >&2; exit 1; }

# save writes the page through pad:pf-save!.
printf '%s\n' 'IN 97' 'IN 9' \
  'IN 115' 'IN 97' 'IN 118' 'IN 101' 'IN 13' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/save.txt" 2>"$OUT/save.err" || { cat "$OUT/save.err" >&2; exit 1; }
grep -q 'saved hello.aura' "$OUT/save.txt" || fail "save did not say saved"
printf 'a(define (hello x) (+ x 1))\n' >"$OUT/hello.want"
cmp -s "$OUT/hello.want" "$OUT/hello.aura" || fail "save did not write the page"
if grep -q 'set_code=' "$OUT/save.txt"; then
  fail "save set-code"
fi

# open rel.aura is the other file in this directory.
printf '%s\n' 'IN 9' \
  'IN 111' 'IN 112' 'IN 101' 'IN 110' 'IN 32' \
  'IN 111' 'IN 116' 'IN 104' 'IN 101' 'IN 114' 'IN 46' \
  'IN 97' 'IN 117' 'IN 114' 'IN 97' 'IN 13' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/open.txt" 2>"$OUT/open.err" || { cat "$OUT/open.err" >&2; exit 1; }
grep -q 'other.aura  aura  new' "$OUT/open.txt" || fail "open did not retitle"
grep -q 'T (define (other y) y)' "$OUT/open.txt" || fail "open did not show the other file"
cmp -s "$OUT/other.orig" "$OUT/other.aura" || fail "open wrote the other file"
if grep -q 'set_code=' "$OUT/open.txt"; then
  fail "open set-code"
fi

# Dirty quit warns once, then the same sentence quits.
# A letter after the second quit must not land.
printf '%s\n' 'IN 97' 'IN 9' \
  'IN 113' 'IN 117' 'IN 105' 'IN 116' 'IN 13' \
  'IN 113' 'IN 117' 'IN 105' 'IN 116' 'IN 13' \
  'IN 122' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/quit.txt" 2>"$OUT/quit.err" || { cat "$OUT/quit.err" >&2; exit 1; }
python3 - "$OUT/quit.txt" "$OUT/hello.aura" "$OUT/hello.want" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
if "is not saved yet" not in text:
    sys.exit("say_file: first quit did not warn")
if text.count("\nLEGEND > quit\n") < 2:
    sys.exit("say_file: first quit left the editor")
if "\nLEGEND > z\n" in text or "\nT z" in text:
    sys.exit("say_file: second quit did not leave")
if "set_code=" in text:
    sys.exit("say_file: quit set-code")
disk = open(sys.argv[2], encoding="utf-8").read()
want = open(sys.argv[3], encoding="utf-8").read()
if disk != want:
    sys.exit("say_file: quit wrote the file")
PY

printf '%s\n' 'IN 24' 'QUIT' | PAD_VI=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/off.txt" 2>"$OUT/off.err" || { cat "$OUT/off.err" >&2; exit 1; }
grep -q 'ctrl-x -' "$OUT/off.txt" || fail "flag off lost ctrl-x"
if grep -q '^LEGEND > ' "$OUT/off.txt"; then
  fail "flag off drew the sentence line"
fi

if grep -qiE 'error:|unbound variable' \
     "$OUT/save.txt" "$OUT/save.err" "$OUT/open.txt" "$OUT/open.err" \
     "$OUT/quit.txt" "$OUT/quit.err" "$OUT/off.txt" "$OUT/off.err"; then
  fail "Soft error"
fi

echo PAD_SAY_FILE_OK
