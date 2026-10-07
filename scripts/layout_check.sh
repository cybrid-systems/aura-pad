#!/usr/bin/env bash
# M15 layout worldlines. Prints PAD_M15_OK. fiber_live only when every
# join landed; otherwise the same race is host-sequential.
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
  echo "layout_check: no aura" >&2
  exit 1
fi
LIB="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$LIB/std" && -d /workspace/aura-grok/lib/std ]]; then
  LIB=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/layout-check"
rm -rf "$OUT"
mkdir -p "$OUT"
export AURA_PATH="$LIB" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off
export AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0
unset PAD_VI PAD_ROWS PAD_COLS || true

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/layout.aura" "$ROOT/soft/pad/layout_test.aura" \
  "$ROOT/soft/pad/win.aura" "$ROOT/soft/pad/rules.aura" \
  "$ROOT/soft/pad/hot.aura"

"$AURA" "$ROOT/soft/pad/layout_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }
cat "$OUT/unit.txt"
if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  echo "layout_check: Soft error" >&2
  cat "$OUT/unit.err" >&2
  exit 1
fi
grep -q '^PAD_M15_OK$' "$OUT/unit.txt" || { echo "layout_check: unit" >&2; exit 1; }
grep -q 'lower-score-rollback' "$OUT/unit.txt"
grep -q 'tie-is-not-better-rollback' "$OUT/unit.txt"
grep -q 'higher-score-stamp' "$OUT/unit.txt"
grep -q 'PAD_M15_UNDO_FAIL' "$OUT/unit.txt"
grep -q 'there is no page to show' "$OUT/unit.txt"
grep -q 'LATENCY before=insert 3.6 ms' "$OUT/unit.txt"

python3 - "$OUT/unit.txt" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
found = False
for m in re.finditer(r"WORLD line=(\S+) backend=(\d+) joins=(\d+)/(\d+)", text):
    found = True
    line, backend, joins, spawned = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))
    if line == "fiber_live":
        if not (backend > 0 and joins == spawned and spawned > 0):
            sys.exit("layout_check: fiber_live " + m.group(0))
    elif line == "host-sequential":
        if joins == spawned and spawned > 0 and backend > 0:
            sys.exit("layout_check: should be fiber_live " + m.group(0))
    else:
        sys.exit("layout_check: bad world line " + m.group(0))
if not found:
    sys.exit("layout_check: no WORLD line")
print("layout_check: world line honest")
PY
