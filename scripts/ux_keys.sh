#!/usr/bin/env bash
# Step 3. Sentence keys only when PAD_SENTENCE=1.
# Page inserts go through pad:play-cmd!. Tab moves focus and does not
# insert byte 9. Scripted hjkl and one insert do not set-code.
# ctrl-x is not a prefix. The flag off still reaches pad:pf-line!.
# Prints PAD_UX_KEYS_OK.
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
  echo "ux_keys: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/ux-keys"
rm -rf "$OUT"
mkdir -p "$OUT"
printf '(define (hello x) (+ x 1))\n' >"$OUT/hello.aura"
cp "$OUT/hello.aura" "$OUT/hello.orig"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/ux.aura" "$ROOT/soft/pad/play.aura"

python3 - "$ROOT" <<'PY'
import sys
root = sys.argv[1]
play = open(root + "/soft/pad/play.aura", encoding="utf-8").read()
ux = open(root + "/soft/pad/ux.aura", encoding="utf-8").read()
keys = open(root + "/soft/pad/keys.aura", encoding="utf-8").read()
loop = play.split("(let loop ()", 1)[1]
on = loop.find("(pad:ux-on?)")
call = loop.find("(pad:ux-key! line)")
pf = loop.find("(pad:pf-line! line)")
step = loop.find("(pad:play-step! line)")
if not (0 <= on < call < pf < step):
    sys.exit("ux_keys: sentence keys are not before the ctrl-x prefix")
if loop.count("pad:ux-key!") != 1:
    sys.exit("ux_keys: pad:ux-key! is not only the flag branch")
edit = ux.split("(define (pad:ux-edit! cmd)", 1)[1].split("\n(define ", 1)[0]
if "pad:play-cmd!" not in edit:
    sys.exit("ux_keys: page insert does not call pad:play-cmd!")
if "pad:ws-load!" in ux or "string-split" in ux:
    sys.exit("ux_keys: sentence keys load the notebook or split strings")
cmd = keys.split("(define (pad:play-cmd! c)", 1)[1].split("\n(define ", 1)[0]
if "(not (and (>= c 32) (<= c 126)))" not in cmd:
    sys.exit("ux_keys: pad:play-cmd! no longer keeps the 32-126 gate")
PY

run_play() {
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/play.aura"
}

fail() { echo "ux_keys: $*" >&2; exit 1; }

# hjkl, one page insert, Tab onto the sentence, a sentence letter,
# Tab back, another page letter, Enter (newline), Esc.
printf '%s\n' \
  'KEY h' 'KEY j' 'KEY k' 'KEY l' \
  'IN 97' \
  'IN 9' 'IN 98' 'IN 9' 'IN 99' \
  'IN 13' 'IN 27' \
  'QUIT' | PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/on.txt" 2>"$OUT/on.err" || { cat "$OUT/on.err" >&2; exit 1; }

python3 - "$OUT/on.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
if "set_code=" in text or "READ " in text:
    sys.exit("ux_keys: hjkl or insert set-code")
if "ctrl-x -" in text:
    sys.exit("ux_keys: ctrl-x became a prefix")
if "that letter is not on the pad yet" in text:
    sys.exit("ux_keys: Tab was refused as a character")
if "\nLEGEND > b\n" not in text:
    sys.exit("ux_keys: Tab did not take the sentence letter")
rows = [ln[2:] for ln in text.splitlines() if ln.startswith("T ")]
if any("\t" in ln or "\x09" in ln for ln in rows):
    sys.exit("ux_keys: Tab inserted byte 9")
if not any(ln.startswith("(a") for ln in rows):
    sys.exit("ux_keys: page insert did not land")
if not any("c" in ln and ln.startswith("(a") for ln in rows):
    sys.exit("ux_keys: focus did not return to the page")
if any(ln.startswith("(b") or ln.startswith("b(") for ln in rows):
    sys.exit("ux_keys: the sentence letter landed on the page")
PY

# A dirty page, then ctrl-x ctrl-s. The file stays the opened bytes.
printf '%s\n' 'IN 97' 'IN 24' 'IN 19' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/cx.txt" 2>"$OUT/cx.err" || { cat "$OUT/cx.err" >&2; exit 1; }
if grep -q 'ctrl-x -' "$OUT/cx.txt"; then
  fail "ctrl-x is still a prefix"
fi
cmp -s "$OUT/hello.orig" "$OUT/hello.aura" || fail "ctrl-x ctrl-s wrote the file"
if ! grep -q 'T a(define' "$OUT/cx.txt"; then
  fail "page insert after ctrl-x did not land"
fi

# Non-empty Enter is not save. Esc clears the draft, then leaves the line.
printf '%s\n' 'IN 9' 'IN 115' 'IN 97' 'IN 118' 'IN 101' 'IN 13' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/later.txt" 2>"$OUT/later.err" || { cat "$OUT/later.err" >&2; exit 1; }
grep -q 'aura cannot change this page yet' "$OUT/later.txt" || fail "Enter did not run the sentence"
if grep -q 'set_code=' "$OUT/later.txt"; then
  fail "a later sentence set-code"
fi
cmp -s "$OUT/hello.orig" "$OUT/hello.aura" || fail "save ran before its step"

printf '%s\n' 'IN 9' 'IN 115' 'IN 97' 'IN 118' 'IN 101' 'IN 27' 'IN 27' 'IN 97' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/esc.txt" 2>"$OUT/esc.err" || { cat "$OUT/esc.err" >&2; exit 1; }
python3 - "$OUT/esc.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
if "\nLEGEND > save\n" not in text or "\nLEGEND > \n" not in text.split("LEGEND > save", 1)[1]:
    sys.exit("ux_keys: Esc did not clear the sentence")
if "set_code=" in text:
    sys.exit("ux_keys: Esc set-code")
rows = [ln[2:] for ln in text.splitlines() if ln.startswith("T ")]
if not any(ln.startswith("a(define") for ln in rows):
    sys.exit("ux_keys: Esc did not return to the page")
PY

# Empty Enter checks. Docker is not required; the hard gate matches run_soft.sh.
printf '%s\n' 'IN 9' 'IN 13' 'IN 9' 'IN 122' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 AURA_MUTATE_TYPE_GATE=hard PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/enter.txt" 2>"$OUT/enter.err" || { cat "$OUT/enter.err" >&2; exit 1; }

# Flag off: ctrl-x still reaches file.aura. Sentence keys are not used.
printf '%s\n' 'IN 24' 'QUIT' | \
  PAD_VI=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/off.txt" 2>"$OUT/off.err" || { cat "$OUT/off.err" >&2; exit 1; }
grep -q 'ctrl-x -' "$OUT/off.txt" || fail "flag off did not reach pad:pf-line!"
if grep -q '^LEGEND > ' "$OUT/off.txt"; then
  fail "flag off drew the sentence line"
fi

if grep -qiE 'error:|unbound variable' \
     "$OUT/on.txt" "$OUT/on.err" "$OUT/cx.txt" "$OUT/cx.err" \
     "$OUT/later.txt" "$OUT/later.err" "$OUT/esc.txt" "$OUT/esc.err" \
     "$OUT/enter.txt" "$OUT/enter.err" "$OUT/off.txt" "$OUT/off.err"; then
  fail "Soft error"
fi

python3 - "$OUT/enter.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
if "born line" not in text:
    sys.exit("ux_keys: empty Enter did not ask the engine")
if text.count("READ set_code=1 eval=1") != 1 or "set_code=2" in text:
    sys.exit("ux_keys: empty Enter was not one set-code")
born = text.find("born line")
again = text.find("check again to ask aura", born)
if again < 0:
    sys.exit("ux_keys: the next page letter left a fresh cache")
if "set_code=" in text[again:]:
    sys.exit("ux_keys: the page letter set-code")
PY

echo PAD_UX_KEYS_OK
