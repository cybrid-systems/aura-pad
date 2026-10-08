#!/usr/bin/env bash
# Step 9. The buffer holds 8000 lines and 4096 scalars.
# The window cap stays 400. A 600-line file stays writable.
# A 4097-column file is look-only, reason too-wide.
# Prints PAD_OPEN_WIDE_OK. Does not call docker.
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
  echo "open_wide: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/open-wide"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/file.aura" \
  "$ROOT/soft/pad/keys.aura" \
  "$ROOT/soft/pad/open_wide_test.aura" \
  "$ROOT/soft/pad/screen.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
file = (root / "soft/pad/file.aura").read_text(encoding="utf-8")
keys = (root / "soft/pad/keys.aura").read_text(encoding="utf-8")
screen = (root / "soft/pad/screen.aura").read_text(encoding="utf-8")
if "(define *pf-max-col* 4096)" not in file:
    sys.exit("open_wide: column cap is not 4096")
if "(define *pf-max-lines* 8000)" not in file:
    sys.exit("open_wide: line cap is not 8000")
if "too-wide" not in file or "too-long" not in file:
    sys.exit("open_wide: look-only reasons missing")
if "vi.aura" not in file or "1469" not in file or "1257" in file:
    sys.exit("open_wide: vi.aura line note is not 1469")
if "*pf-max-col*" not in keys or "4096" not in keys:
    sys.exit("open_wide: file mode does not name the buffer cap")
if "pad:vw-cap c 400" not in screen:
    sys.exit("open_wide: window cap moved")
if "pad:vw-cap c 4096" in screen or "pad:vw-cap c 8000" in screen:
    sys.exit("open_wide: window cap was raised")
PY

python3 - "$OUT" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
(out / "rows600.aura").write_text("".join("x\n" for _ in range(600)), encoding="ascii")
(out / "rows8001.aura").write_text("".join("y\n" for _ in range(8001)), encoding="ascii")
(out / "cols500.aura").write_text("a" * 500 + "\n", encoding="ascii")
(out / "cols4096.aura").write_text("b" * 4096 + "\n", encoding="ascii")
(out / "cols4097.aura").write_text("c" * 4097 + "\n", encoding="ascii")
(out / "rows600.orig").write_bytes((out / "rows600.aura").read_bytes())
(out / "cols4097.orig").write_bytes((out / "cols4097.aura").read_bytes())
PY

fail() { echo "open_wide: $*" >&2; exit 1; }

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  AURA_MUTATE_TYPE_GATE=hard \
  PAD_ROWS_FILE="$OUT/rows600.aura" \
  PAD_COLS500="$OUT/cols500.aura" \
  PAD_COLS4096="$OUT/cols4096.aura" \
  PAD_COLS4097="$OUT/cols4097.aura" \
  PAD_ROWS8001="$OUT/rows8001.aura" \
  "$AURA" "$ROOT/soft/pad/open_wide_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

grep -q 'OPEN_WIDE_UNIT_OK' "$OUT/unit.txt" || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; fail "unit did not finish"; }
grep -q 'ROWS open=ok ro=false lines=600 len=1 max-col=4096' "$OUT/unit.txt" || fail "600 lines were not writable"
grep -q 'SAVE600 saved' "$OUT/unit.txt" || fail "600-line save refused"
cmp -s "$OUT/rows600.orig" "$OUT/rows600.aura" || fail "600-line save changed the bytes"
grep -q 'COLS500 open=ok ro=false lines=1 len=500 max-col=4096' "$OUT/unit.txt" || fail "500 columns were cut or look-only"
grep -q 'COLS4096 open=ok ro=false lines=1 len=4096 max-col=4096' "$OUT/unit.txt" || fail "4096 columns were look-only"
grep -q 'COLS4097 open=ro ro=true' "$OUT/unit.txt" || fail "4097 columns were writable"
grep -q 'too-wide' "$OUT/unit.txt" || fail "4097 columns had no too-wide reason"
grep -q 'SAVE4097 ro' "$OUT/unit.txt" || fail "4097-column save did not return ro"
cmp -s "$OUT/cols4097.orig" "$OUT/cols4097.aura" || fail "look-only save wrote the file"
grep -q 'ROWS8001 open=ro ro=true' "$OUT/unit.txt" || fail "8001 lines were writable"
grep -q 'too-long' "$OUT/unit.txt" || fail "8001 lines had no too-long reason"
if grep -q 'set_code=' "$OUT/unit.txt"; then
  fail "unit set-code"
fi

echo PAD_OPEN_WIDE_OK
