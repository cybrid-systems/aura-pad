#!/usr/bin/env bash
# M14 windows: Soft unit tests, host byte-oracle, thin C blit of the
# multi-window snap. Prints PAD_M14_OK from Soft and PAD_M14_MODEL_OK.
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
  echo "win_check: no aura" >&2
  exit 1
fi
LIB="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$LIB/std" && -d /workspace/aura-grok/lib/std ]]; then
  LIB=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/win-check"
rm -rf "$OUT"
mkdir -p "$OUT"
export AURA_PATH="$LIB" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off
export AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0
unset PAD_VI PAD_ROWS PAD_COLS || true

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/win.aura" "$ROOT/soft/pad/win_test.aura" \
  "$ROOT/soft/pad/screen.aura" "$ROOT/soft/pad/vi.aura" \
  "$ROOT/soft/pad/file.aura" "$ROOT/soft/pad/play.aura"

"$AURA" "$ROOT/soft/pad/win_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }
cat "$OUT/unit.txt"
if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  echo "win_check: Soft error" >&2
  cat "$OUT/unit.err" >&2
  exit 1
fi
grep -q '^PAD_M14_OK$' "$OUT/unit.txt" || { echo "win_check: unit" >&2; exit 1; }

python3 "$ROOT/scripts/win_model.py" /tmp/aura-pad-m14.snap

bash "$ROOT/scripts/build_c.sh"
"$ROOT/out/c/pad_view" --plain /tmp/aura-pad-m14.snap >"$OUT/blit.txt" 2>"$OUT/blit.err"
grep -q 'say:' "$OUT/blit.txt" || { echo "win_check: blit" >&2; cat "$OUT/blit.txt" >&2; exit 1; }
# Overlapping rectangles are dropped whole.
cat >"$OUT/bad.snap" <<'EOF'
SNAP v1 pad
TITLE t
CURSOR line=0 col=0
SAY hi
LEGEND x
WINS n=2
WIN r=0 c=0 h=2 w=8 sel=1 top=0 left=0 cy=0 cx=0 st=0 wh=0
T 1234567|
H ........
M ........
T 1234567|
H ........
M ........
WIN r=0 c=0 h=2 w=8 sel=0 top=0 left=0 cy=0 cx=0 st=0 wh=0
T 1234567|
H ........
M ........
T 1234567|
H ........
M ........
END
EOF
if "$ROOT/out/c/pad_view" --plain "$OUT/bad.snap" >"$OUT/bad.txt" 2>"$OUT/bad.err"; then
  echo "win_check: overlap was accepted" >&2
  exit 1
fi
echo "win_check: overlap dropped"
