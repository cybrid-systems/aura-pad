#!/usr/bin/env bash
# Step 5. UTF-8 scalars on the page, one ASCII cell on the frame.
# Paste of E2 80 94 is one scalar. A lone IN 226 does not insert.
# Prints PAD_UTF8_OK. Does not call docker.
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
  echo "utf8: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/utf8"
rm -rf "$OUT"
mkdir -p "$OUT"
FIX="$ROOT/soft/pad/fixtures/marks.aura"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/utf.aura" \
  "$ROOT/soft/pad/utf_test.aura" \
  "$ROOT/soft/pad/view.aura" \
  "$ROOT/soft/pad/lines.aura" \
  "$ROOT/soft/pad/lc.aura" \
  "$ROOT/soft/pad/play_in.aura" \
  "$ROOT/soft/pad/keys.aura" \
  "$ROOT/soft/pad/file.aura" \
  "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/play.aura" \
  "$ROOT/soft/pad/hl.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
banned = ("string-split", "string-trim", "string-replace")
files = [
    "soft/pad/utf.aura",
    "soft/pad/utf_test.aura",
    "soft/pad/lines.aura",
    "soft/pad/lc.aura",
    "soft/pad/play_in.aura",
    "soft/pad/keys.aura",
    "soft/pad/file.aura",
    "soft/pad/ux.aura",
    "soft/pad/play.aura",
]
for rel in files:
    text = (root / rel).read_text(encoding="utf-8")
    for word in banned:
        if word in text:
            sys.exit("utf8: " + rel + " contains " + word)
view = (root / "soft/pad/view.aura").read_text(encoding="utf-8")
body = view.split("(define (pad:v-src L)", 1)[1].split("(define ", 1)[0]
if "pad:utf-encode" not in body or "pad:utf-fold" in body:
    sys.exit("utf8: pad:v-src must encode and must not fold")
if "pad:utf-fold-src" not in view:
    sys.exit("utf8: oracle does not fold")
lc = (root / "soft/pad/lc.aura").read_text(encoding="utf-8")
if lc.count("(list->string (map pad:utf-fold codes))") < 2:
    sys.exit("utf8: line cache does not fold both sites")
pin = (root / "soft/pad/play_in.aura").read_text(encoding="utf-8")
if pin.count("(list->string (map pad:utf-fold ln2))") < 2:
    sys.exit("utf8: end-of-row insert does not fold")
if "(pad:ux-scalar? c)" not in pin or "(or (<= c 126) (> c 255))" not in pin:
    sys.exit("utf8: ins still takes a raw high byte")
if "(< b 256)" not in pin and "(< b 256)" not in pin.replace(" ", ""):
    pass
keys = (root / "soft/pad/keys.aura").read_text(encoding="utf-8")
step = keys.split("(define (pad:key-step", 1)[1].split("(define ", 1)[0]
if "(<= b 126)" not in step:
    sys.exit("utf8: pad:key-step was widened")
if keys.count("(pad:ux-scalar? c)") < 2:
    sys.exit("utf8: gate was not widened")
raw = (root / "soft/pad/fixtures/marks.aura").read_bytes()
if b"\xe2\x80\x94" not in raw or b"\xe2\x86\x92" not in raw:
    sys.exit("utf8: fixture is missing the mark bytes")
PY

# The single-byte bound in play_in stays under 256.
if ! grep -q '< b 256' "$ROOT/soft/pad/play_in.aura"; then
  # the source uses "(< b 256)" with possible spacing
  if ! grep -F -q '(< b 256)' "$ROOT/soft/pad/play_in.aura"; then
    echo "utf8: play_in byte bound moved" >&2
    exit 1
  fi
fi

printf '(define (mark x) x)\n' >"$OUT/page.aura"
cp "$OUT/page.aura" "$OUT/page.orig"
printf '(define (mark x) x)\n' >"$OUT/split.aura"
printf '(define (mark x) x)\n' >"$OUT/badseq.aura"
printf '(define (mark x) x)\n' >"$OUT/c1.aura"
printf '(define (mark x) x)\n' >"$OUT/over.aura"
printf '(define (mark x) x)\n' >"$OUT/save.aura"
python3 -c 'open("'"$OUT"'/bad.aura","wb").write(bytes([0xff, 0x0a]))'
python3 -c 'open("'"$OUT"'/tab.aura","wb").write(b"a\tb\n")'

run_play() {
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    AURA_MUTATE_TYPE_GATE=hard \
    "$AURA" "$ROOT/soft/pad/play.aura"
}

fail() { echo "utf8: $*" >&2; exit 1; }

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  AURA_MUTATE_TYPE_GATE=hard \
  PAD_FILE="$FIX" PAD_UTF_BAD="$OUT/bad.aura" PAD_UTF_TAB="$OUT/tab.aura" \
  "$AURA" "$ROOT/soft/pad/utf_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

grep -q 'UTF8_UNIT_OK' "$OUT/unit.txt" || { cat "$OUT/unit.txt" >&2; fail "unit did not finish"; }
grep -q 'GOOD open=ok ro=false' "$OUT/unit.txt" || fail "fixture opened look-only"
grep -q 'SAME true' "$OUT/unit.txt" || { cat "$OUT/unit.txt" >&2; fail "frame and oracle differ"; }
grep -q 'ROUND true' "$OUT/unit.txt" || fail "encode did not round-trip the fixture"
grep -q 'VSRC 226' "$OUT/unit.txt" || fail "pad:v-src folded the em dash"
grep -q 'TAPE 45' "$OUT/unit.txt" || fail "tape did not fold"
grep -q 'SCALAR 226 true' "$OUT/unit.txt" || fail "226 is not a scalar"
grep -q 'SCALAR 8212 true' "$OUT/unit.txt" || fail "8212 is not a scalar"
for n in 10 13 127 128 159 55296 1114112; do
  grep -q "SCALAR $n false" "$OUT/unit.txt" || fail "scalar $n was accepted"
  grep -q "GATE $n not-print" "$OUT/unit.txt" || fail "gate $n was not not-print"
  grep -q "CMD $n not-print" "$OUT/unit.txt" || fail "cmd $n was not not-print"
done
grep -q 'GATE 226 ok' "$OUT/unit.txt" || fail "gate 226"
grep -q 'GATE 8212 ok' "$OUT/unit.txt" || fail "gate 8212"
grep -q 'CMD 226 ok' "$OUT/unit.txt" || fail "cmd 226"
grep -q 'CMD 8212 ok' "$OUT/unit.txt" || fail "cmd 8212"
grep -q 'KEY226 unknown' "$OUT/unit.txt" || fail "key-step accepted 226"
grep -q 'BAD open=ro ro=true' "$OUT/unit.txt" || fail "bad utf-8 was editable"
grep -q 'bad-utf8' "$OUT/unit.txt" || fail "bad utf-8 had no reason"
grep -q 'TAB open=ro ro=true' "$OUT/unit.txt" || fail "tab was editable"
if grep -q 'set_code=' "$OUT/unit.txt"; then
  fail "unit set-code"
fi
python3 - "$OUT/unit.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
frame = text.split("FRAME\n", 1)[1].split("ORACLE\n", 1)[0]
if ";; - >" not in frame:
    sys.exit("utf8: frame cells are not '-' and '>'")
for line in frame.splitlines():
    if line.startswith("T ") or line.startswith("H ") or line.startswith("M "):
        body = line[2:]
        if len(line) < 2:
            sys.exit("utf8: short row")
# lengths of each T/H/M triple
rows = [ln[2:] for ln in frame.splitlines() if ln[:2] in ("T ", "H ", "M ")]
if len(rows) % 3 != 0:
    sys.exit("utf8: row triple is short")
for i in range(0, len(rows), 3):
    if not (len(rows[i]) == len(rows[i + 1]) == len(rows[i + 2])):
        sys.exit("utf8: |T| |H| |M| differ")
if any(b > 126 for b in frame.encode("utf-8", "surrogateescape")):
    # the file was decoded as utf-8 text; cells must be ASCII
    sys.exit("utf8: frame row is not ASCII")
PY

# Cursor on the em dash, then on the arrow.
printf '%s\n' 'KEY l' 'KEY l' 'KEY l' 'KEY l' 'KEY l' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$FIX" \
  run_play >"$OUT/move.txt" 2>"$OUT/move.err" || { cat "$OUT/move.err" >&2; exit 1; }
python3 - "$OUT/move.txt" <<'PY'
import sys
raw = open(sys.argv[1], "rb").read()
if b"\xe2\x80\x94" not in raw:
    sys.exit("utf8: SAY is missing the em dash")
if b"\xe2\x86\x92" not in raw:
    sys.exit("utf8: SAY is missing the arrow")
if b"look only" in raw:
    sys.exit("utf8: fixture is look-only")
text = raw.decode("utf-8", "surrogateescape")
if ";; - >" not in text:
    sys.exit("utf8: move frame lost the folded cells")
# the cell row itself stays ASCII; the raw mark lives in SAY
for line in text.splitlines():
    if line.startswith("T ") and "define" not in line and line != "T ":
        if any(c > "\x7e" for c in line):
            sys.exit("utf8: T row holds a raw scalar")
PY

# A lone lead does not insert.
printf '%s\n' 'IN 226' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/page.aura" \
  run_play >"$OUT/lone.txt" 2>"$OUT/lone.err" || { cat "$OUT/lone.err" >&2; exit 1; }
cmp -s "$OUT/page.orig" "$OUT/page.aura" || fail "lone IN 226 wrote the file"
python3 - "$OUT/lone.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
rows = [ln for ln in text.splitlines() if ln.startswith("T ")]
if not rows or rows[-1] != "T (define (mark x) x)":
    sys.exit("utf8: lone IN 226 inserted a cell: " + (rows[-1] if rows else "none"))
PY

# One protocol line pastes one scalar.
printf '%s\n' 'IN 226 128 148' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/save.aura" \
  run_play >"$OUT/paste.txt" 2>"$OUT/paste.err" || { cat "$OUT/paste.err" >&2; exit 1; }
python3 - "$OUT/paste.txt" <<'PY'
import sys
raw = open(sys.argv[1], "rb").read()
text = raw.decode("utf-8", "surrogateescape")
rows = [ln for ln in text.splitlines() if ln.startswith("T ")]
if not rows or not rows[-1].startswith("T -("):
    sys.exit("utf8: paste frame cell is not '-': " + (rows[-1] if rows else "none"))
if b"this mark is \xe2\x80\x94" not in raw:
    sys.exit("utf8: paste SAY is missing the raw mark")
PY

# Save writes E2 80 94, not the folded hyphen.
printf '%s\n' 'IN 226 128 148' 'IN 9' \
  'IN 115' 'IN 97' 'IN 118' 'IN 101' 'IN 13' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/save.aura" \
  run_play >"$OUT/save.txt" 2>"$OUT/save.err" || { cat "$OUT/save.err" >&2; exit 1; }
python3 - "$OUT/save.aura" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
want = b"\xe2\x80\x94(define (mark x) x)\n"
if b != want:
    sys.exit("utf8: save bytes " + b.hex())
if b"\x2d" in b:
    sys.exit("utf8: save wrote the folded hyphen")
PY
grep -q 'saved save.aura' "$OUT/save.txt" || fail "paste save did not say saved"
if grep -q 'set_code=' "$OUT/save.txt"; then
  fail "paste save set-code"
fi

# The same scalar split across reads.
printf '%s\n' 'IN 226' 'IN 128' 'IN 148' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/split.aura" \
  run_play >"$OUT/split.txt" 2>"$OUT/split.err" || { cat "$OUT/split.err" >&2; exit 1; }
python3 - "$OUT/split.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
rows = [ln for ln in text.splitlines() if ln.startswith("T ")]
if not rows or not rows[-1].startswith("T -("):
    sys.exit("utf8: split paste did not insert one cell")
PY

printf '%s\n' 'IN 128' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/badseq.aura" \
  run_play >"$OUT/badseq.txt" 2>"$OUT/badseq.err" || { cat "$OUT/badseq.err" >&2; exit 1; }
grep -q 'SAY bad utf8' "$OUT/badseq.txt" || fail "bad sequence SAY"
python3 - "$OUT/badseq.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
rows = [ln for ln in text.splitlines() if ln.startswith("T ")]
if not rows or rows[-1] != "T (define (mark x) x)":
    sys.exit("utf8: bad sequence inserted")
PY

printf '%s\n' 'IN 194 128' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/c1.aura" \
  run_play >"$OUT/c1.txt" 2>"$OUT/c1.err" || { cat "$OUT/c1.err" >&2; exit 1; }
grep -q 'SAY not-print' "$OUT/c1.txt" || fail "C1 SAY"
python3 - "$OUT/c1.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
rows = [ln for ln in text.splitlines() if ln.startswith("T ")]
if not rows or rows[-1] != "T (define (mark x) x)":
    sys.exit("utf8: C1 inserted")
PY

printf '%s\n' 'IN 192 128' 'QUIT' | \
  PAD_VI=1 PAD_SENTENCE=1 PAD_FILE="$OUT/over.aura" \
  run_play >"$OUT/over.txt" 2>"$OUT/over.err" || { cat "$OUT/over.err" >&2; exit 1; }
grep -q 'SAY bad utf8' "$OUT/over.txt" || fail "overlong SAY"

echo PAD_UTF8_OK
