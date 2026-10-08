#!/usr/bin/env bash
# Step 16. A wide line scrolls inside the window. The window cap stays 400.
# Prints PAD_SCROLL_WIDE_OK. Does not call docker.
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
  echo "scroll_wide: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/scroll-wide"
rm -rf "$OUT"
mkdir -p "$OUT"
python3 - "$OUT/wide.aura" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text("a" * 450 + "Z" + "a" * 49 + "\n", encoding="ascii")
PY

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/file.aura" \
  "$ROOT/soft/pad/screen.aura" \
  "$ROOT/soft/pad/scroll_wide_test.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
file = (root / "soft/pad/file.aura").read_text(encoding="utf-8")
screen = (root / "soft/pad/screen.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/scroll_wide_test.aura").read_text(encoding="utf-8")
reset = file.find("(pad:play-reset! \"\")")
cap = file.find("(set! *max-col* *pf-max-col*)", reset)
if reset < 0 or cap < 0:
    sys.exit("scroll_wide: open does not keep the buffer column cap")
if "pad:vw-cap c 400" not in screen:
    sys.exit("scroll_wide: window cap moved")
if "pad:vw-cap c 4096" in screen or "pad:vw-cap c 8000" in screen:
    sys.exit("scroll_wide: window cap was raised")
if "pad:vw-scroll" not in screen:
    sys.exit("scroll_wide: the window no longer scrolls")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test or banned in file:
        sys.exit("scroll_wide: banned text " + banned)
PY

fail() { echo "scroll_wide: $*" >&2; exit 1; }

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SCROLL_FILE="$OUT/wide.aura" \
  "$AURA" "$ROOT/soft/pad/scroll_wide_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|need-space' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "Soft error"
fi
grep -qx 'SCROLL_UNIT_OK' "$OUT/unit.txt" || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; fail "unit did not finish"; }
grep -qx 'SCROLL open=ok ro=false len=500 max-col=4096' "$OUT/unit.txt" || fail "500 columns did not open writable"
grep -qx 'SCROLL fit=true' "$OUT/unit.txt" || fail "the slice is wider than the window"
grep -qx 'SCROLL at-col=Z' "$OUT/unit.txt" || fail "column 450 is not in the slice"
grep -qx 'SCROLL insert=ok len-after=501' "$OUT/unit.txt" || fail "insert stopped at the window"
grep -qx 'SCROLL cap=400' "$OUT/unit.txt" || fail "the window cap is no longer 400"
echo PAD_SCROLL_WIDE_OK
