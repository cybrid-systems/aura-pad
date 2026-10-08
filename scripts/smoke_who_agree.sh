#!/usr/bin/env bash
# Step 30. Engine who against the existing Soft row stamp.
# Agreement logs verdict=agree. A forged stamp logs M11_WHO_DISAGREE.
# Does not call docker. Prints PAD_WHO_AGREE_OK.
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
  echo "smoke_who_agree: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/who-agree"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/eng_who.aura" \
  "$ROOT/soft/pad/who_agree_test.aura"

fail() { echo "smoke_who_agree: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
ew = (root / "soft/pad/eng_who.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/who_agree_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in ew or banned in test:
        sys.exit("smoke_who_agree: banned text " + banned)
if "pad:who-stamp-of" not in ew:
    sys.exit("smoke_who_agree: does not read the row stamp")
if "pad:ew-verdict" not in ew:
    sys.exit("smoke_who_agree: does not cross-check")
if "M11_WHO_DISAGREE" not in ew:
    sys.exit("smoke_who_agree: missing the disagree line")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SENTENCE=1 \
  "$AURA" "$ROOT/soft/pad/who_agree_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi
grep -qx 'WHO_AGREE_UNIT_OK' "$OUT/unit.txt" || fail "unit did not finish"

python3 - "$OUT/unit.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
agree = [i for i, ln in enumerate(lines) if "verdict=agree" in ln and "M11_WHO_DISAGREE" not in ln]
bad = [i for i, ln in enumerate(lines) if ln.startswith("M11_WHO_DISAGREE")]
if not agree:
    sys.exit("smoke_who_agree: no verdict=agree")
if not bad:
    sys.exit("smoke_who_agree: forged stamp was not detected")
if not (agree[0] < bad[0]):
    sys.exit("smoke_who_agree: disagree came before agreement")
if "who=helper" not in lines[agree[0]] or "soft=helper" not in lines[agree[0]]:
    sys.exit("smoke_who_agree: agree line is not the helper stamp: " + lines[agree[0]])
if "soft=macro" not in lines[bad[0]]:
    sys.exit("smoke_who_agree: disagree line is not the forged stamp: " + lines[bad[0]])
PY

echo PAD_WHO_AGREE_OK
