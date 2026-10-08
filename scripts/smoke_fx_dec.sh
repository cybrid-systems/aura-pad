#!/usr/bin/env bash
# Step 55. fix_loop and kid_rules no longer call the std cutter.
# A multi-line name=(lambda ...) decodes. "tab 4" yields the name and the number.
# play.aura and ux.aura do not load those two files. Does not call docker.
# Prints PAD_FX_DEC_OK.
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
  echo "smoke_fx_dec: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/fx-dec"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "smoke_fx_dec: $*" >&2; exit 1; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/fx_dec_test.aura" \
  "$ROOT/soft/pad/fix_loop.aura" \
  "$ROOT/soft/pad/kid_rules.aura" \
  "$ROOT/soft/pad/why.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
banned = ("string-split", "string-trim", "string-replace")
for rel in ("soft/pad/fix_loop.aura", "soft/pad/kid_rules.aura",
            "soft/pad/fx_dec_test.aura"):
    text = (root / rel).read_text(encoding="utf-8")
    for word in banned:
        if word in text:
            sys.exit(f"smoke_fx_dec: {rel} still names {word}")
for rel in ("soft/pad/play.aura", "soft/pad/ux.aura"):
    text = (root / rel).read_text(encoding="utf-8")
    for name in ("fix_loop.aura", "kid_rules.aura"):
        if name in text:
            sys.exit(f"smoke_fx_dec: {rel} names {name}")
if "pad:why-cut" not in (root / "soft/pad/fix_loop.aura").read_text(encoding="utf-8"):
    sys.exit("smoke_fx_dec: fix_loop does not cut on string-index")
if "pad:why-cut" not in (root / "soft/pad/kid_rules.aura").read_text(encoding="utf-8"):
    sys.exit("smoke_fx_dec: kid_rules does not cut on string-index")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/fx_dec_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi
for line in \
  "CHECK dec=ok" \
  "CHECK round=ok" \
  "CHECK blank=ok" \
  "CHECK not-str=ok" \
  "CHECK tab=ok" \
  "CHECK tab-gap=ok" \
  "CHECK tab-num=ok" \
  "CHECK hist=ok" \
  "FX_DEC_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
echo "PAD_FX_DEC_OK"
