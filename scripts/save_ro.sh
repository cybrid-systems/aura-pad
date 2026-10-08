#!/usr/bin/env bash
# Step 19. Look-only save returns ro and leaves the disk bytes alone.
# Prints PAD_RO_OK. Does not call docker.
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
  echo "save_ro: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/save-ro"
rm -rf "$OUT"
mkdir -p "$OUT"
python3 - "$OUT" "$ROOT" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
(out / "bad.aura").write_bytes(b";; ok\xff\n(define (x) x)\n")
(out / "wide.aura").write_text("c" * 4097 + "\n", encoding="ascii")
(out / "good.aura").write_bytes((root / "soft/pad/fixtures/marks.aura").read_bytes())
for name in ("bad.aura", "wide.aura", "good.aura"):
    data = (out / name).read_bytes()
    (out / (name + ".orig")).write_bytes(data)
PY

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/file.aura" \
  "$ROOT/soft/pad/save_ro_test.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
file = (root / "soft/pad/file.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/save_ro_test.aura").read_text(encoding="utf-8")

def body(src, name):
    key = "(define (" + name
    i = src.find(key)
    if i < 0:
        sys.exit("save_ro: missing " + name)
    j = src.find("\n(define ", i + 1)
    if j < 0:
        j = len(src)
    return src[i:j]

save = body(file, "pad:pf-save!)")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test:
        sys.exit("save_ro: banned word " + banned)
if "(if *pf-ro*" not in save:
    sys.exit("save_ro: save does not refuse a look-only page")
ro_at = save.find('"ro"')
write_at = save.find("write-file")
if ro_at < 0 or write_at < 0 or ro_at > write_at:
    sys.exit("save_ro: look-only save can still write")
if "pad:pf-cut" in save:
    sys.exit("save_ro: save writes a cut page")
if "bad-utf8" not in file or "too-wide" not in file:
    sys.exit("save_ro: open does not name the reason")
PY

fail() { echo "save_ro: $*" >&2; exit 1; }

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_RO_BAD="$OUT/bad.aura" PAD_RO_WIDE="$OUT/wide.aura" PAD_RO_GOOD="$OUT/good.aura" \
  "$AURA" "$ROOT/soft/pad/save_ro_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "Soft error"
fi
grep -qx 'SAVE_RO_UNIT_OK' "$OUT/unit.txt" || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; fail "unit did not finish"; }
grep -qx 'BAD open=ro ro=true len=6 reason=bad-utf8' "$OUT/unit.txt" || fail "bad utf-8 was editable"
grep -qx 'BAD save=ro' "$OUT/unit.txt" || fail "bad utf-8 save did not return ro"
grep -qx 'WIDE open=ro ro=true len=4096 reason=too-wide' "$OUT/unit.txt" || fail "too-wide page was writable"
grep -qx 'WIDE save=ro' "$OUT/unit.txt" || fail "too-wide save did not return ro"
grep -qx 'GOOD open=ok ro=false len=6 reason=none' "$OUT/unit.txt" || fail "legal utf-8 was look-only"
grep -qx 'GOOD save=saved' "$OUT/unit.txt" || fail "legal utf-8 save took the ro path"
cmp -s "$OUT/bad.aura.orig" "$OUT/bad.aura" || fail "bad utf-8 save changed the file"
cmp -s "$OUT/wide.aura.orig" "$OUT/wide.aura" || fail "too-wide save changed the file"
cmp -s "$OUT/good.aura.orig" "$OUT/good.aura" || fail "legal utf-8 save changed the file"
python3 - "$OUT" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
bad = (out / "bad.aura").read_bytes()
wide = (out / "wide.aura").read_bytes()
if b"\xff" not in bad:
    sys.exit("save_ro: invalid byte was replaced")
if len(wide) != 4098:
    sys.exit("save_ro: wide file was cut to %d" % len(wide))
PY
echo PAD_RO_OK
