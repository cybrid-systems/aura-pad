#!/usr/bin/env bash
# Step 59. Arrows do not load the rule file or the intend file.
# Native aura only. Prints PAD_LAZY_RULE_OK.
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
  echo "smoke_m24: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/m24"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "smoke_m24: $*" >&2; exit 1; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/lazy_rule_test.aura" \
  "$ROOT/soft/pad/play.aura" \
  "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/tx.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
play = (root / "soft/pad/play.aura").read_text(encoding="utf-8")
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/lazy_rule_test.aura").read_text(encoding="utf-8")

def body(src, name):
    key = "(define (" + name
    a = src.find(key)
    if a < 0:
        sys.exit("smoke_m24: missing " + name)
    b = src.find("\n(define ", a + 1)
    return src[a:] if b < 0 else src[a:b]

for name in ("fix_loop.aura", "kid_rules.aura"):
    if name in play or name in ux or name in test:
        sys.exit("smoke_m24: load list names " + name)
top = "\n".join(play.splitlines()[:45])
if "fix_loop" in top or "kid_rules" in top:
    sys.exit("smoke_m24: play top loads a late file")
for name in ("pad:ux-arrow! ", "pad:ux-move! ", "pad:ux-key! "):
    part = body(ux, name)
    for banned in ("pad:tx-kr-ready!", "pad:tx-fix", "pad:kr-cmd!", "fix_loop", "kid_rules"):
        if banned in part:
            sys.exit("smoke_m24: " + name + " loads a late file")
if "pad:tx-kr-ready!" not in body(ux, "pad:ux-rule! "):
    sys.exit("smoke_m24: tab does not load the rule file")
if "fix_loop.aura" not in body(tx, "pad:tx-fix-ready!"):
    sys.exit("smoke_m24: repair does not load the intend file")
if "kid_rules.aura" not in body(tx, "pad:tx-kr-ready!)"):
    sys.exit("smoke_m24: the rule loader lost its file")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SENTENCE=1 \
  "$AURA" "$ROOT/soft/pad/lazy_rule_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak|M11_FIX_DISAGREE|M11_RULES_DISAGREE' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi
for line in \
  "CHECK arrows-kr=ok" \
  "CHECK arrows-fx=ok" \
  "CHECK set_code=ok" \
  "set_code=0" \
  "CHECK rules=ok" \
  "CHECK tab-kr=ok" \
  "CHECK tab-fx=ok" \
  "CHECK tab-value=ok" \
  "CHECK hello=ok" \
  "CHECK fix-fx=ok" \
  "CHECK fix-tag=ok" \
  "LAZY_RULE_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
echo "PAD_LAZY_RULE_OK"
