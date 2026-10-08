#!/usr/bin/env bash
# Step 12. Birth marks use pad:defs-for on the projection.
# Prints PAD_READ_MARK_OK. Does not call docker.
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
  echo "read_mark: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/read-mark"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/read.aura" \
  "$ROOT/soft/pad/jump.aura" \
  "$ROOT/soft/pad/read_mark_test.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
read = (root / "soft/pad/read.aura").read_text(encoding="utf-8")
jump = (root / "soft/pad/jump.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/read_mark_test.aura").read_text(encoding="utf-8")

def body(src, name):
    key = "(define (" + name
    i = src.find(key)
    if i < 0:
        sys.exit("read_mark: missing " + name)
    j = src.find("\n(define ", i + 1)
    if j < 0:
        j = len(src)
    return src[i:j]

gather = body(read, "pad:read-gather! ")
dat = body(jump, "pad:jump-d-at ")
letter = body(jump, "pad:jump-mark-letter ")
arm = gather[gather.find("(let ((jsrc *pad-jump-src*))"):]
if arm.startswith("(let ((jsrc *pad-jump-src*))") is False:
    sys.exit("read_mark: gather does not copy the jump source")
if arm.find("pad:read-back!") < 0 or arm.find("*pad-jump-src*") > arm.find("pad:read-back!"):
    sys.exit("read_mark: jump source is read after the switch")
if 'READ jump=' not in gather:
    sys.exit("read_mark: gather does not log the jump source")
if "pad:defs-for" not in dat:
    sys.exit("read_mark: birth point does not call pad:defs-for")
if '"d"' not in letter:
    sys.exit("read_mark: mark letter is not d")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in read or banned in jump or banned in test:
        sys.exit("read_mark: banned text " + banned)
if "gd" in dat or "gd" in letter:
    sys.exit("read_mark: new jump helper is a key")
PY

fail() { echo "read_mark: $*" >&2; exit 1; }

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/read_mark_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "Soft error"
fi
grep -qx 'MARK_UNIT_OK' "$OUT/unit.txt" || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; fail "unit did not finish"; }
grep -qx 'MARK miss-src=hl+engine' "$OUT/unit.txt" || fail "mismatched engine line was used as engine"
grep -qx 'MARK miss-letter=d' "$OUT/unit.txt" || fail "mismatched line did not mark the name"
grep -qx 'MARK miss-on-name=true' "$OUT/unit.txt" || fail "mark missed the projected name"
grep -qx 'MARK miss-not-col=true' "$OUT/unit.txt" || fail "cursor used the engine column"
grep -qx 'MARK miss-bytes=same' "$OUT/unit.txt" || fail "stub changed the projection"
grep -qx 'MARK status=checked' "$OUT/unit.txt" || fail "page was not checked"
js=$(sed -n 's/^MARK jump=//p' "$OUT/unit.txt" | head -n 1)
case "$js" in
  engine|hl+engine) ;;
  *) fail "jump source is ${js:-missing}" ;;
esac
grep -qx "READ jump=$js" "$OUT/unit.txt" || fail "log jump is not $js"
grep -qx 'MARK letter=d' "$OUT/unit.txt" || fail "checked page mark is not d"
grep -qx 'MARK on-name=true' "$OUT/unit.txt" || fail "checked mark missed the name"
grep -qx 'MARK bytes=same' "$OUT/unit.txt" || fail "check changed the projection"
grep -qx 'MARK say=clear' "$OUT/unit.txt" || fail "check wrote SAY"
echo PAD_READ_MARK_OK
