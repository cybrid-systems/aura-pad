#!/usr/bin/env bash
# M17 living storybook. Prints PAD_M17_OK. The C viewport does not
# learn the words celebration or storybook.
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
  echo "story_check: no aura" >&2
  exit 1
fi
LIB="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$LIB/std" && -d /workspace/aura-grok/lib/std ]]; then
  LIB=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/story-check"
rm -rf "$OUT"
mkdir -p "$OUT"
export AURA_PATH="$LIB" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off
export AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0
unset PAD_VI PAD_ROWS PAD_COLS || true

if grep -nE '"[^"]*(celebration|storybook)[^"]*"' "$ROOT"/c/*.c "$ROOT"/c/*.h; then
  echo "story_check: C learned celebration or storybook" >&2
  exit 1
fi

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/story.aura" "$ROOT/soft/pad/story_test.aura" \
  "$ROOT/soft/pad/win.aura" "$ROOT/soft/pad/layout.aura"

"$AURA" "$ROOT/soft/pad/story_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }
cat "$OUT/unit.txt"
if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  echo "story_check: Soft error" >&2
  cat "$OUT/unit.err" >&2
  exit 1
fi
grep -q '^PAD_M17_OK$' "$OUT/unit.txt" || { echo "story_check: unit" >&2; exit 1; }
grep -q 'this page is growing!' "$OUT/unit.txt" \
  || { echo "story_check: missing grow say" >&2; exit 1; }
grep -q 'almost there!' "$OUT/unit.txt" \
  || { echo "story_check: missing mood say" >&2; exit 1; }
grep -q 'celebration page opened' "$OUT/unit.txt" \
  || { echo "story_check: missing cheer say" >&2; exit 1; }
grep -q 'that page would be too big' "$OUT/unit.txt" \
  || { echo "story_check: missing too big" >&2; exit 1; }
grep -q 'that page would be too tiny' "$OUT/unit.txt" \
  || { echo "story_check: missing too tiny" >&2; exit 1; }
grep -q 'PAD_M17_UNDO_FAIL' "$OUT/unit.txt" \
  || { echo "story_check: missing undo fail" >&2; exit 1; }
grep -q 'T hook OK' "$OUT/unit.txt" \
  || { echo "story_check: lazy hook" >&2; exit 1; }
grep -q 'storybook is not on the key path' "$OUT/unit.txt" \
  || { echo "story_check: latency line" >&2; exit 1; }

python3 - "$OUT/unit.txt" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
found = False
for m in re.finditer(r"WORLD line=(\S+) backend=(\d+) joins=(\d+)/(\d+)", text):
    found = True
    line, backend, joins, spawned = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))
    if line == "fiber_live":
        if not (backend > 0 and joins == spawned and spawned > 0):
            sys.exit("story_check: fiber_live " + m.group(0))
    elif line == "host-sequential":
        if joins == spawned and spawned > 0 and backend > 0:
            sys.exit("story_check: should be fiber_live " + m.group(0))
    else:
        sys.exit("story_check: bad world line " + m.group(0))
if not found:
    sys.exit("story_check: no WORLD line")
print("story_check: world line honest")
PY

python3 - "$OUT/unit.txt" "$OUT/cheer.snap" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"ORACLE line=(\d+) col=(\d+) top=(\d+) left=(\d+)", text)
if not m:
    sys.exit("story_check: no oracle")
line, col, top, left = [int(x) for x in m.groups()]
idx = text.rfind("SNAP v1 pad")
if idx < 0:
    sys.exit("story_check: no snap")
snap = text[idx:]
end = snap.find("\nEND\n")
if end < 0:
    sys.exit("story_check: no END")
snap = snap[:end + 5]
open(sys.argv[2], "w").write(snap)
sel = None
for ln in snap.splitlines():
    if ln.startswith("WIN ") and "sel=1" in ln.split():
        fields = dict(p.split("=", 1) for p in ln[4:].split())
        sel = ln
        if int(fields["top"]) != top or int(fields["left"]) != left:
            sys.exit("story_check: window-start " + ln)
        cy = line - top
        cx = col - left
        if cy < 0:
            cy = 0
        if cx < 0:
            cx = 0
        if int(fields["cy"]) != cy or int(fields["cx"]) != cx:
            sys.exit("story_check: point " + ln)
        break
if sel is None:
    sys.exit("story_check: no selected window")
print("story_check: oracle matches point and window-start")
PY

python3 "$ROOT/scripts/win_model.py" "$OUT/cheer.snap"
