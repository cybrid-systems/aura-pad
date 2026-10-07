#!/usr/bin/env bash
# M16 preview windows. Prints PAD_M16_OK. The C viewport must not
# learn the words helper or preview.
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
  echo "preview_check: no aura" >&2
  exit 1
fi
LIB="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$LIB/std" && -d /workspace/aura-grok/lib/std ]]; then
  LIB=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/preview-check"
rm -rf "$OUT"
mkdir -p "$OUT"
export AURA_PATH="$LIB" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off
export AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0
unset PAD_VI PAD_ROWS PAD_COLS || true

if grep -nE '"[^"]*(helper|preview)[^"]*"' "$ROOT"/c/*.c "$ROOT"/c/*.h; then
  echo "preview_check: C learned helper or preview" >&2
  exit 1
fi

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/preview.aura" "$ROOT/soft/pad/preview_test.aura" \
  "$ROOT/soft/pad/win.aura"

"$AURA" "$ROOT/soft/pad/preview_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }
cat "$OUT/unit.txt"
if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  echo "preview_check: Soft error" >&2
  cat "$OUT/unit.err" >&2
  exit 1
fi
grep -q '^PAD_M16_OK$' "$OUT/unit.txt" || { echo "preview_check: unit" >&2; exit 1; }
grep -q 'Look, the helper made a new page next to yours!' "$OUT/unit.txt" \
  || { echo "preview_check: missing look say" >&2; exit 1; }
grep -q 'your page kept the new one!' "$OUT/unit.txt" \
  || { echo "preview_check: missing keep say" >&2; exit 1; }
grep -q 'keeping your page' "$OUT/unit.txt" \
  || { echo "preview_check: missing drop say" >&2; exit 1; }
grep -q 'higher-score-stamp' "$OUT/unit.txt" \
  || { echo "preview_check: missing keep stamp" >&2; exit 1; }
grep -q 'lower-score-rollback' "$OUT/unit.txt" \
  || { echo "preview_check: missing worse drop" >&2; exit 1; }
grep -q 'tie-is-not-better-rollback' "$OUT/unit.txt" \
  || { echo "preview_check: missing tie drop" >&2; exit 1; }
grep -q 'PAD_M16_UNDO_FAIL' "$OUT/unit.txt" \
  || { echo "preview_check: missing undo fail" >&2; exit 1; }
grep -q 'PREVIEW who=helper st=1' "$OUT/unit.txt" \
  || { echo "preview_check: missing preview line" >&2; exit 1; }
grep -q 'T hook OK' "$OUT/unit.txt" \
  || { echo "preview_check: lazy hook" >&2; exit 1; }

python3 - "$OUT/unit.txt" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
found = False
for m in re.finditer(r"WORLD line=(\S+) backend=(\d+) joins=(\d+)/(\d+)", text):
    found = True
    line, backend, joins, spawned = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))
    if line == "fiber_live":
        if not (backend > 0 and joins == spawned and spawned > 0):
            sys.exit("preview_check: fiber_live " + m.group(0))
    elif line == "host-sequential":
        if joins == spawned and spawned > 0 and backend > 0:
            sys.exit("preview_check: should be fiber_live " + m.group(0))
    else:
        sys.exit("preview_check: bad world line " + m.group(0))
if not found:
    sys.exit("preview_check: no WORLD line")
print("preview_check: world line honest")
PY
