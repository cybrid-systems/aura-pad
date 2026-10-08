#!/usr/bin/env bash
# Step 58. The sentence tab 4 swaps a page rule.
# Native aura only. Prints PAD_RULE_OK.
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
  echo "smoke_rule: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/rule"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "smoke_rule: $*" >&2; exit 1; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/rule_test.aura" \
  "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/hot.aura" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/kid_rules.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
hot = (root / "soft/pad/hot.aura").read_text(encoding="utf-8")
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
kr = (root / "soft/pad/kid_rules.aura").read_text(encoding="utf-8")
play = (root / "soft/pad/play.aura").read_text(encoding="utf-8")
pen = (root / "soft/pad/pen.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/rule_test.aura").read_text(encoding="utf-8")

def body(src, name):
    key = "(define (" + name
    a = src.find(key)
    if a < 0:
        sys.exit("smoke_rule: missing " + name)
    b = src.find("\n(define ", a + 1)
    return src[a:] if b < 0 else src[a:b]

for rel, text in (("ux", ux), ("play", play), ("test", test)):
    if "kid_rules.aura" in text:
        sys.exit("smoke_rule: " + rel + " names the rule file")
if "kid_rules.aura" not in tx:
    sys.exit("smoke_rule: the rule file is not loaded on the sentence")
intent = body(ux, "pad:say-intent ")
if '"tab "' not in intent or intent.find('"tab "') > intent.find("later"):
    sys.exit("smoke_rule: tab falls through")
if "pad:ux-rule!" not in body(ux, "pad:say-run!)"):
    sys.exit("smoke_rule: the sentence does not run the rule")
rule = body(ux, "pad:ux-rule! ")
if "pad:kr-cmd!" not in rule:
    sys.exit("smoke_rule: the sentence does not call pad:kr-cmd!")
for banned in ("pad:pen-gate", "pad:kr-propose!"):
    if banned in rule or banned in body(ux, "pad:ux-rule-hot! "):
        sys.exit("smoke_rule: the sentence calls " + banned)
arrow = body(ux, "pad:ux-arrow! ")
for banned in ("load", "kid_rules", "pad:tx-kr-ready!", "pad:kr-cmd!", "pad:hs-rule"):
    if banned in arrow:
        sys.exit("smoke_rule: arrow path touches the rule")
cmd = body(kr, "pad:kr-cmd! ")
if '(pad:kr-write! "kid"' not in cmd:
    sys.exit("smoke_rule: pad:kr-cmd! does not write who kid")
swap = body(hot, "pad:hs-rule-swap! ")
if "pad:hs-register!" not in swap or "hot-strategy:swap!" not in swap:
    sys.exit("smoke_rule: the swap does not register and swap")
if "hot-strategy:register!" in swap:
    sys.exit("smoke_rule: bare register skips the snapshot heal")
if "current-time-ms" not in body(hot, "pad:hs-rule-log! "):
    sys.exit("smoke_rule: the swap log has no milliseconds")
heal = body(hot, "pad:hs-rule-heal! ")
if "hot-strategy:heal!" not in heal or "hot-strategy:swap!" not in heal:
    sys.exit("smoke_rule: an out-of-range body does not heal")
whos = ""
for line in pen.splitlines():
    if "*pen-whos*" in line:
        whos = line
        break
if whos == "" or "kid" in whos:
    sys.exit("smoke_rule: pen whos contains kid")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test or banned in tx[tx.find("(define (pad:tx-kr-ready!)"):]:
        sys.exit("smoke_rule: banned text " + banned)
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SENTENCE=1 \
  "$AURA" "$ROOT/soft/pad/rule_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak|M11_RULES_DISAGREE' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi
for line in \
  "CHECK intent-tab=ok" \
  "CHECK intent-bare=ok" \
  "CHECK intent-table=ok" \
  "CHECK intent-nope=ok" \
  "CHECK bound-before=ok" \
  "CHECK load=ok" \
  "CHECK bound-after=ok" \
  "CHECK verdict=ok" \
  "CHECK value=ok" \
  "CHECK say=ok" \
  "CHECK fp=ok" \
  "CHECK who=ok" \
  "CHECK pen=ok" \
  "CHECK swaps=ok" \
  "CHECK heal-value=ok" \
  "CHECK heal-say=ok" \
  "CHECK heals=ok" \
  "CHECK fp-kept=ok" \
  "CHECK who-kept=ok" \
  "RULE_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
swaps="$(grep -cE '^SWAP name=tab-size ms=[0-9]+$' "$OUT/unit.txt" || true)"
heals="$(grep -cE '^HEAL name=tab-size ms=[0-9]+$' "$OUT/unit.txt" || true)"
if [[ "$swaps" != "1" ]]; then
  fail "swap log count $swaps"
fi
if [[ "$heals" != "1" ]]; then
  fail "heal log count $heals"
fi
echo "PAD_RULE_OK"
