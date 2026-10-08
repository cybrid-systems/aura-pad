#!/usr/bin/env bash
# Step 18. A dirty save re-encodes scalars and keeps comment bytes.
# Prints PAD_SAVE_DIRTY_OK. Does not call docker.
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
  echo "save_dirty: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/save-dirty"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$ROOT/soft/pad/fixtures/marks.aura" "$OUT/marks.aura"
cp "$OUT/marks.aura" "$OUT/marks.orig"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/file.aura" \
  "$ROOT/soft/pad/save_dirty_test.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
file = (root / "soft/pad/file.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/save_dirty_test.aura").read_text(encoding="utf-8")

def body(src, name):
    key = "(define (" + name
    i = src.find(key)
    if i < 0:
        sys.exit("save_dirty: missing " + name)
    j = src.find("\n(define ", i + 1)
    if j < 0:
        j = len(src)
    return src[i:j]

save = body(file, "pad:pf-save!)")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in file or banned in test:
        sys.exit("save_dirty: banned word " + banned)
if "pad:utf-fold" in save:
    sys.exit("save_dirty: save writes a fold cell")
if "(if clean\n                       *pf-saved*\n                       (pad:utf-encode (pad:es-L *pl-st*)))" not in save:
    sys.exit("save_dirty: dirty arm does not encode scalars")
if "(set! *pf-saved* text)" not in save:
    sys.exit("save_dirty: saved bytes are not the encoding")
if "query:code" in save:
    sys.exit("save_dirty: save asks query:code for the text")
PY

fail() { echo "save_dirty: $*" >&2; exit 1; }

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SAVE_DIRTY="$OUT/marks.aura" \
  "$AURA" "$ROOT/soft/pad/save_dirty_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "Soft error"
fi
grep -qx 'SAVE_DIRTY_UNIT_OK' "$OUT/unit.txt" || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; fail "unit did not finish"; }
grep -qx 'DIRTY open=ok ro=false nl=true encode=saved' "$OUT/unit.txt" || fail "page was not a clean UTF-8 open"
grep -qx 'DIRTY was=109 now=110 cmp=diff fold=same' "$OUT/unit.txt" || fail "the letter change did not dirty the encoding"
grep -qx 'DIRTY save=saved' "$OUT/unit.txt" || fail "dirty save did not save"
grep -qx 'DIRTY stored=encode dash=bytes' "$OUT/unit.txt" || fail "saved text is not the scalar encoding"

python3 - "$OUT" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
orig = (out / "marks.orig").read_bytes()
saved = (out / "marks.aura").read_bytes()
if len(orig) != len(saved):
    sys.exit("save_dirty: length changed %d -> %d" % (len(orig), len(saved)))
diffs = [i for i, (a, b) in enumerate(zip(orig, saved)) if a != b]
if diffs != [orig.index(b"(define (mark") + len(b"(define (")]:
    sys.exit("save_dirty: unexpected diffs %s" % diffs)
i = diffs[0]
if orig[i] != 109 or saved[i] != 110:
    sys.exit("save_dirty: byte %d is %d -> %d" % (i, orig[i], saved[i]))
dash = b"\xe2\x80\x94"
arrow = b"\xe2\x86\x92"
if orig.count(dash) != 1 or saved.count(dash) != 1:
    sys.exit("save_dirty: em dash count changed")
if orig.count(arrow) != 1 or saved.count(arrow) != 1:
    sys.exit("save_dirty: arrow count changed")
if b"(define (nark x) x)\n" not in saved:
    sys.exit("save_dirty: the changed line was not written")
PY
echo PAD_SAVE_DIRTY_OK
