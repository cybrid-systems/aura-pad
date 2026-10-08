#!/usr/bin/env bash
# Step 31. KEEP serializes the file child before workspace:delete.
# The projection file has no notebook row tag. Does not call docker.
# Prints PAD_AW_OK.
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
  echo "smoke_aw: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/aw"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/read.aura" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/aw_test.aura"

fail() { echo "smoke_aw: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
read = (root / "soft/pad/read.aura").read_text(encoding="utf-8")
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/aw_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in read or banned in tx or banned in test:
        sys.exit("smoke_aw: banned text " + banned)
for banned in ("pad:time-open!", "pad:book-open!", "std/persist"):
    if banned in read or banned in tx or banned in test:
        sys.exit("smoke_aw: banned call " + banned)
if "serialize-workspace" not in read or "workspace-persist-info" not in read:
    sys.exit("smoke_aw: sidecar writer is missing")
if "pad-nb-rows" in read or "pad-nb-rows" in tx:
    sys.exit("smoke_aw: writer mentions the notebook tag")
key = "(define (pad:read-aw! "
i = read.find(key)
if i < 0:
    sys.exit("smoke_aw: missing pad:read-aw!")
j = read.find("\n(define ", i + 1)
body = read[i:] if j < 0 else read[i:j]
if "workspace:delete" in body or "workspace :delete" in body:
    sys.exit("smoke_aw: serialize deletes a workspace")
if "serialize-workspace" not in body:
    sys.exit("smoke_aw: pad:read-aw! does not serialize")
keep = tx.find("(define (pad:tx-keep! ")
if keep < 0:
    sys.exit("smoke_aw: missing pad:tx-keep!")
nxt = tx.find("\n(define ", keep + 1)
kbody = tx[keep:] if nxt < 0 else tx[keep:nxt]
aw = kbody.find("(pad:read-aw! c out)")
hold = kbody.find("(pad:tx-hold! c)", aw if aw >= 0 else 0)
if aw < 0 or hold < 0 or not (aw < hold):
    sys.exit("smoke_aw: sidecar is not written while the file child is current")
tail = kbody[aw:]
if "workspace:delete" in tail or "workspace :delete" in tail:
    sys.exit("smoke_aw: KEEP deletes the child it just serialized")
hkey = tx.find("(define (pad:tx-hold! ")
hnxt = tx.find("\n(define ", hkey + 1)
hbody = tx[hkey:] if hnxt < 0 else tx[hkey:hnxt]
if "workspace:delete" in hbody or "workspace :delete" in hbody:
    sys.exit("smoke_aw: hold deletes the file child")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SENTENCE=1 AURA_PAD_AW_FILE="$OUT/page.aura" \
  "$AURA" "$ROOT/soft/pad/aw_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

for line in \
  "CHECK say=helper changed hello" \
  "AW same=yes" \
  "AW before-delete=yes" \
  "AW wrote=1" \
  "AW proj=wrote" \
  "CHECK aw-bytes=some" \
  "CHECK proj-tag=absent" \
  "CHECK aw-tag=absent" \
  "AW_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done

if grep -q 'AW crc-bad' "$OUT/unit.txt"; then
  fail "crc mismatch"
fi
if grep -qx 'AW crc-ok' "$OUT/unit.txt"; then
  :
elif grep -qx 'AW crc=unbound' "$OUT/unit.txt"; then
  :
else
  fail "persist info was neither crc-ok nor unbound"
fi

python3 - "$OUT/unit.txt" "$OUT/page.aura" "$OUT/page.aura.aw" <<'PY'
import pathlib, sys
log = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines()
proj = pathlib.Path(sys.argv[2]).read_bytes()
aw = pathlib.Path(sys.argv[3]).read_bytes()
if not aw:
    sys.exit("smoke_aw: empty sidecar")
if b"pad-nb-rows" in proj or b"pad-nb-rows" in aw:
    sys.exit("smoke_aw: notebook tag in a written file")

def first(prefix):
    for ln in log:
        if ln.startswith(prefix):
            return ln[len(prefix):]
    sys.exit("smoke_aw: missing " + prefix)

child = first("APPLY child=")
here = first("AW workspace=")
want = first("AW child=")
if not (child == here == want):
    sys.exit("smoke_aw: serialize workspace %s child %s apply %s" % (here, want, child))
same = log.index("AW same=yes")
wrote = log.index("AW wrote=1")
if not (same < wrote):
    sys.exit("smoke_aw: workspace was not the child at the write")
PY

echo PAD_AW_OK
