#!/usr/bin/env bash
# Step 27. A multi-line define is spliced back. The comment above stays.
# A form longer than 120 lands. A missing name leaves the page.
# Does not call docker. Prints PAD_SPLICE_OK.
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
  echo "smoke_splice: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/splice"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" "$ROOT/soft/pad/splice_test.aura"

fail() { echo "smoke_splice: $*" >&2; exit 1; }

python3 - "$ROOT/soft/pad/tx.aura" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in src:
        sys.exit("smoke_splice: tx.aura contains " + banned)
key = "(define (pad:proj-splice! "
i = src.find(key)
if i < 0:
    sys.exit("smoke_splice: missing pad:proj-splice!")
j = src.find("\n(define ", i + 1)
body = src[i:] if j < 0 else src[i:j]
if "pad:find-defs-in" not in body:
    sys.exit("smoke_splice: splice does not use pad:find-defs-in")
if "query:code" in body or "pad:pen-project" in body:
    sys.exit("smoke_splice: splice reprints or uses the pen path")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/splice_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

for line in \
  "CHECK comment=same" \
  "CHECK prefix=same" \
  "CHECK long=landed" \
  "CHECK tail=same" \
  "CHECK missing=same" \
  "CHECK pen-path=multi-line" \
  "CHECK pen-page=same" \
  "CHECK root=same" \
  "CHECK sane=true" \
  "SPLICE_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
n=$(sed -n 's/^CHECK form-n=//p' "$OUT/unit.txt" | head -n 1)
if [[ -z "$n" || "$n" -le 120 ]]; then
  fail "form is not longer than 120 (${n:-missing})"
fi
echo "PAD_SPLICE_OK"
