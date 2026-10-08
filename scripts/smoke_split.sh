#!/usr/bin/env bash
# Step 24. who / why / time no longer call the std cutter.
# The replacement is a string-index recursion, same shape as pad:pf-split.
# Does not call docker. Prints PAD_SPLIT_OK.
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
  echo "smoke_split: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/split"
rm -rf "$OUT"
mkdir -p "$OUT"

files=(
  "$ROOT/soft/pad/eng_who.aura"
  "$ROOT/soft/pad/who_pen.aura"
  "$ROOT/soft/pad/why.aura"
  "$ROOT/soft/pad/time.aura"
)
python3 "$ROOT/scripts/paren_check.py" "${files[@]}" "$ROOT/soft/pad/split_test.aura"

fail() { echo "smoke_split: $*" >&2; exit 1; }

for f in "${files[@]}"; do
  if grep -n -E 'string-split|string-trim|string-replace' "$f"; then
    fail "$(basename "$f") still names a std cut"
  fi
  grep -q 'view.aura lines 17-18' "$f" || fail "$(basename "$f") missing the view note"
  grep -q '18b48dc' "$f" || fail "$(basename "$f") missing the pin note"
  grep -q 'docs/ISSUES.md' "$f" || fail "$(basename "$f") missing the issues note"
  grep -q 'string-index' "$f" || fail "$(basename "$f") missing string-index"
  grep -q 'not measure a return' "$f" || fail "$(basename "$f") missing the no-measure note"
done

# Step 55 removed the std cutter from the two files step 24 left alone.
if grep -q 'string-split' "$ROOT/soft/pad/fix_loop.aura"; then
  fail "fix_loop.aura still names the std cutter"
fi
if grep -q 'string-split' "$ROOT/soft/pad/kid_rules.aura"; then
  fail "kid_rules.aura still names the std cutter"
fi

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/split_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  fail "Soft error"
fi
for line in \
  "CHECK ew-rec=ok" \
  "CHECK ew-empty=ok" \
  "CHECK ew-gap=ok" \
  "CHECK csv=ok" \
  "CHECK csv-tail=ok" \
  "CHECK dirty-all=ok" \
  "CHECK dirty-rows=ok" \
  "CHECK why=ok" \
  "CHECK why-skip=ok" \
  "CHECK rows=ok" \
  "CHECK story=ok" \
  "CHECK stamp=ok" \
  "CHECK nl=ok" \
  "CHECK dots=ok" \
  "SPLIT_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
echo "PAD_SPLIT_OK"
