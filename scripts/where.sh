#!/usr/bin/env bash
# Step 13. where answers from the cache.
# Prints PAD_WHERE_OK. Does not call docker.
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
  echo "where: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/where"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/where_test.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/where_test.aura").read_text(encoding="utf-8")

def body(src, name):
    key = "(define (" + name
    i = src.find(key)
    if i < 0:
        sys.exit("where: missing " + name)
    j = src.find("\n(define ", i + 1)
    if j < 0:
        j = len(src)
    return src[i:j]

intent = body(ux, "pad:say-intent ")
ask = body(ux, "pad:ux-where! ")
say = body(ux, "pad:ux-where-say ")
if '(string=? line "where")' not in intent:
    sys.exit("where: bare where is not an intent")
if '"where "' not in intent:
    sys.exit("where: named where is not an intent")
if intent.find('(string=? line "where")') > intent.find("later"):
    sys.exit("where: where falls through")
if "pad:ux-check!" not in ask or '"checked"' not in ask:
    sys.exit("where: stale cache is not checked")
if ask.find('"checked"') > ask.find("pad:ux-check!"):
    sys.exit("where: a fresh cache is checked again")
if "pad:ux-say-of" not in say:
    sys.exit("where: the answer does not come from the cache row")
if "define-lookup" in say or "set-code" in say:
    sys.exit("where: the fresh answer calls the engine")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in ux or banned in test:
        sys.exit("where: banned text " + banned)
PY

fail() { echo "where: $*" >&2; exit 1; }

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SENTENCE=1 \
  "$AURA" "$ROOT/soft/pad/where_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "Soft error"
fi
grep -qx 'WHERE_UNIT_OK' "$OUT/unit.txt" || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; fail "unit did not finish"; }
for line in \
  "WHERE bare-intent=where" \
  "WHERE named-intent=hello" \
  "WHERE partial=later" \
  "WHERE glued=later" \
  "WHERE sym=hello" \
  "WHERE fresh-set=0" \
  "WHERE named-set=0" \
  "WHERE same=true" \
  "WHERE status=checked" \
  "WHERE stale-set=1" \
  "WHERE stale-same=true" \
  "WHERE stale-status=checked" \
  "WHERE alias-sym=tcp-connect" \
  "WHERE alias-same=true" \
  "WHERE alias-set=0" \
  "WHERE alias-used0=true"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
grep -q '^WHERE say=hello born line ' "$OUT/unit.txt" || fail "hello SAY is not a birth sentence"
grep -q '^WHERE alias-say=tcp-connect born line ' "$OUT/unit.txt" || fail "alias SAY is not a birth sentence"
echo PAD_WHERE_OK
