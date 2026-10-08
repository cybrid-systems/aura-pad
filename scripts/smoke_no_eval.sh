#!/usr/bin/env bash
# Step 57. The repair verifier does not eval a generated closure.
# A fixture that would pass that way is refused and points at aura#4359.
# Does not call docker. Prints PAD_NO_EVAL_OK.
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
  echo "smoke_no_eval: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/no-eval"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "smoke_no_eval: $*" >&2; exit 1; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/m24_cases.aura" \
  "$ROOT/soft/pad/fix_loop.aura" \
  "$ROOT/soft/pad/tx.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
fx = (root / "soft/pad/fix_loop.aura").read_text(encoding="utf-8")
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
needle = "(eval "

def body(src, name):
    key = "(define (" + name
    a = src.find(key)
    if a < 0:
        sys.exit("smoke_no_eval: missing " + name)
    b = src.find("\n(define ", a + 1)
    return src[a:] if b < 0 else src[a:b]

if needle in fx:
    sys.exit("smoke_no_eval: fix_loop verifier evals")
for name in ("pad:fx-verify ", "pad:fx-fix ", "pad:fx-run! ", "pad:fx-tx! "):
    if needle in body(fx, name):
        sys.exit("smoke_no_eval: " + name + "evals")
for name in ("pad:tx-fix-ready!", "pad:tx-fix! "):
    if needle in body(tx, name):
        sys.exit("smoke_no_eval: " + name + "evals")
if "pad:world-run1" not in body(fx, "pad:fx-verify "):
    sys.exit("smoke_no_eval: verifier lost the child world")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/m24_cases.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi
if grep -q '^FAIL aura#4359$' "$OUT/unit.txt"; then
  cat "$OUT/unit.txt" >&2
  fail "the eval fixture counted as a pass"
fi
for line in \
  "CHECK plain=ok" \
  "CHECK refused=ok" \
  "CHECK no-pass=ok" \
  "CHECK issue=ok" \
  "CHECK point=aura#4359" \
  "NO_EVAL_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
echo "PAD_NO_EVAL_OK"
