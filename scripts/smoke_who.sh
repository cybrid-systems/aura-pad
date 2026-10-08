#!/usr/bin/env bash
# Step 29. who answers from query:node-provenance.
# After apply, the cursor define's SAY contains helper and the sum text.
# An untouched define says nobody has changed this yet.
# Does not call docker. Prints PAD_WHO_SAY_OK.
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
  echo "smoke_who: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/who"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/eng_who.aura" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/who_say_test.aura"

fail() { echo "smoke_who: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
ew = (root / "soft/pad/eng_who.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/who_say_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in ux or banned in ew or banned in test:
        sys.exit("smoke_who: banned text " + banned)
if "git blame" in ew or "git blame" in ux or "git blame" in test:
    sys.exit("smoke_who: git blame")
if "eng_who" in ux:
    sys.exit("smoke_who: sentence line names the who file")
if '(string=? line "who")' not in ux:
    sys.exit("smoke_who: who is not a sentence")
if "query:node-provenance" not in ew:
    sys.exit("smoke_who: provenance is not asked")
key = "(define (pad:ew-say-name "
i = ew.find(key)
if i < 0:
    sys.exit("smoke_who: missing pad:ew-say-name")
j = ew.find("\n(define ", i + 1)
body = ew[i:] if j < 0 else ew[i:j]
if "pad:ew-prov" not in body:
    sys.exit("smoke_who: who does not ask provenance")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SENTENCE=1 \
  "$AURA" "$ROOT/soft/pad/who_say_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

grep -qx 'CHECK say=helper changed hello' "$OUT/unit.txt" || fail "apply did not keep"
grep -qx 'CHECK fresh=nobody has changed this yet' "$OUT/unit.txt" || fail "comment row"
grep -qx 'CHECK hello-name=hello' "$OUT/unit.txt" || fail "cursor missed hello"
grep -qx 'CHECK main-name=main' "$OUT/unit.txt" || fail "cursor missed main"
grep -qx 'CHECK main=nobody has changed this yet' "$OUT/unit.txt" || fail "untouched define"
grep -qx 'CHECK page=same' "$OUT/unit.txt" || fail "who changed the page"
grep -qx 'WHO_SAY_UNIT_OK' "$OUT/unit.txt" || fail "unit did not finish"

python3 - "$OUT/unit.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read().splitlines()
def need(prefix):
    rows = [ln[len(prefix):] for ln in text if ln.startswith(prefix)]
    if len(rows) != 1:
        sys.exit("smoke_who: missing " + prefix)
    say = rows[0]
    if "helper" not in say or "closer" not in say:
        sys.exit("smoke_who: SAY missing helper or sum: " + say)

need("CHECK who=")
need("CHECK again=")
PY

echo PAD_WHO_SAY_OK
