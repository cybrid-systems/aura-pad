#!/usr/bin/env bash
# Step 23. The projection round-trips. query:code is not the page.
# A clean save matches the opened bytes. A comment edit stays in the
# projection, and the check log says query:code differs.
# Does not call docker. Prints PAD_M19_OK.
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
  echo "smoke_m19: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/m19"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$ROOT/soft/pad/fixtures/greet.aura" "$OUT/greet.aura"
cp "$OUT/greet.aura" "$OUT/greet.orig"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/read.aura" "$ROOT/soft/pad/m19_test.aura"

python3 - "$ROOT/soft/pad/fixtures/greet.aura" <<'PY'
import pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_bytes()
if b"\xe2\x80\x94" not in raw:
    sys.exit("smoke_m19: fixture has no em dash")
text = raw.decode("utf-8")
if ";;" not in text:
    sys.exit("smoke_m19: fixture has no comment")
if "(define (greet name)\n" not in text:
    sys.exit("smoke_m19: fixture define is not multi-line")
if ".aw" in text:
    sys.exit("smoke_m19: fixture mentions a sidecar")
PY

fail() { echo "smoke_m19: $*" >&2; exit 1; }

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_M19_FILE="$OUT/greet.aura" \
  "$AURA" "$ROOT/soft/pad/m19_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|READ_DISAGREE|GAPS define-lookup|GAPS read-leak|GAPS query:dirty-nodes' \
     "$OUT/unit.txt" "$OUT/unit.err"; then
  fail "Soft error or leak"
fi
for line in \
  "CHECK open=ok" \
  "CHECK ro=false" \
  "CHECK dash=bytes" \
  "CHECK first=checked" \
  "CHECK save=saved" \
  "CHECK clean=same" \
  "CHECK status=checked" \
  "CHECK say=nothing is dirty" \
  "CHECK proj=kept" \
  "CHECK dirty-save=saved" \
  "M19_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
if grep -q 'READ query:code=same' "$OUT/unit.txt"; then
  fail "query:code matched the projection"
fi
if grep -q 'READ query:code=empty' "$OUT/unit.txt"; then
  fail "query:code was empty"
fi
grep -q 'READ query:code=differ ' "$OUT/unit.txt" || fail "missing query:code contrast"
python3 - "$OUT/greet.orig" "$OUT/greet.aura" "$OUT/unit.txt" <<'PY'
import pathlib, sys
orig = pathlib.Path(sys.argv[1]).read_bytes().splitlines()
new = pathlib.Path(sys.argv[2]).read_bytes().splitlines()
log = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").splitlines()
if len(orig) != len(new):
    sys.exit("smoke_m19: line count changed")
diff = [i for i, (a, b) in enumerate(zip(orig, new)) if a != b]
if diff != [0]:
    sys.exit("smoke_m19: more than the comment line changed: " + str(diff))
if b"edited note" not in new[0] or b"\xe2\x80\x94" not in new[0]:
    sys.exit("smoke_m19: edited comment lost the note or the em dash")
if b"\xe2\x80\x94" not in b"\n".join(new):
    sys.exit("smoke_m19: em dash was folded")
rows = [ln for ln in log if ln.startswith("READ query:code=")]
if len(rows) < 2:
    sys.exit("smoke_m19: expected a contrast on both checks")
for ln in rows:
    parts = ln.split()
    proj = code = None
    for p in parts:
        if p.startswith("proj="):
            proj = int(p.split("=", 1)[1])
        elif p.startswith("code="):
            code = int(p.split("=", 1)[1])
    if proj is None or code is None or proj == code:
        sys.exit("smoke_m19: lengths do not contrast: " + ln)
PY
if find "$OUT" -name '*.aw' | grep -q .; then
  fail "a sidecar was written"
fi
echo PAD_M19_OK
