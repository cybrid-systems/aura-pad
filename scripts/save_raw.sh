#!/usr/bin/env bash
# Step 17. A clean save writes the original bytes.
# Prints PAD_SAVE_RAW_OK. Does not call docker.
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
  echo "save_raw: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/save-raw"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$ROOT/soft/pad/fixtures/marks.aura" "$OUT/marks.aura"
cp "$OUT/marks.aura" "$OUT/marks.orig"
python3 - "$OUT/none.aura" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_bytes(b";; \xe2\x80\x94\n(define (mark x) x)")
PY
cp "$OUT/none.aura" "$OUT/none.orig"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/file.aura" \
  "$ROOT/soft/pad/save_raw_test.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
file = (root / "soft/pad/file.aura").read_text(encoding="utf-8")
vi = (root / "soft/pad/vi.aura").read_text(encoding="utf-8")

def body(src, name):
    key = "(define (" + name
    i = src.find(key)
    if i < 0:
        sys.exit("save_raw: missing " + name)
    j = src.find("\n(define ", i + 1)
    if j < 0:
        j = len(src)
    return src[i:j]

opened = body(file, "pad:pf-open! ")
save = body(file, "pad:pf-save!)")
quitb = body(file, "pad:pf-quit! ")
vq = body(vi, "pad:vi-quit-name")
if "(set! *pf-saved* s)" not in opened:
    sys.exit("save_raw: open does not keep the pre-decode bytes")
if "pad:v-src" in opened or "pad:utf-fold" in opened:
    sys.exit("save_raw: open folds or re-encodes the saved bytes")
if "*pf-saved*" not in save:
    sys.exit("save_raw: save does not write the captured bytes")
if "(string=? (pad:play-src) *pf-saved*)" not in quitb:
    sys.exit("save_raw: quit no longer compares the encoding")
if vq.count("(string=? (pad:play-src) *pf-saved*)") < 1:
    sys.exit("save_raw: vi quit no longer compares the encoding")
if vi.count("(string=? (pad:play-src) *pf-saved*)") < 2:
    sys.exit("save_raw: vi lost a saved comparison")
PY

fail() { echo "save_raw: $*" >&2; exit 1; }

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SAVE_RAW="$OUT/marks.aura" PAD_SAVE_NONE="$OUT/none.aura" \
  "$AURA" "$ROOT/soft/pad/save_raw_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "Soft error"
fi
grep -qx 'SAVE_RAW_UNIT_OK' "$OUT/unit.txt" || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; fail "unit did not finish"; }
grep -qx 'RAW open=ok ro=false nl=true encode=saved play=saved dash=bytes' "$OUT/unit.txt" || fail "em dash page was not clean"
grep -qx 'RAW save=saved' "$OUT/unit.txt" || fail "clean save did not save"
grep -qx 'RAW quit=quit' "$OUT/unit.txt" || fail "clean page looked dirty"
grep -qx 'NONE open=ok ro=false nl=false encode=saved play=saved dash=bytes' "$OUT/unit.txt" || fail "no-newline page was not clean"
grep -qx 'NONE save=saved' "$OUT/unit.txt" || fail "no-newline save did not save"
cmp -s "$OUT/marks.orig" "$OUT/marks.aura" || fail "clean save changed the em dash file"
cmp -s "$OUT/none.orig" "$OUT/none.aura" || fail "clean save changed the no-newline file"
if grep -q $'\xe2\x80\x94' "$OUT/marks.aura"; then
  :
else
  fail "saved file lost the em dash"
fi
echo PAD_SAVE_RAW_OK
