#!/usr/bin/env bash
# Step 33. undo and byte 26 roll back one KEEP, text and author.
# Does not call docker. Prints PAD_UNDO_WHO_OK.
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
  echo "smoke_undo: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/undo"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/read.aura" \
  "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/undo_test.aura"

fail() { echo "smoke_undo: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
read = (root / "soft/pad/read.aura").read_text(encoding="utf-8")
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in tx or banned in read or banned in (root / "soft/pad/undo_test.aura").read_text(encoding="utf-8"):
        sys.exit("smoke_undo: banned text " + banned)
key = "(define (pad:tx-undo!)"
i = tx.find(key)
if i < 0:
    sys.exit("smoke_undo: missing pad:tx-undo!")
j = tx.find("\n(define ", i + 1)
body = tx[i:] if j < 0 else tx[i:j]
if "set-code" in body:
    sys.exit("smoke_undo: undo set-code")
if "ast:restore" not in body or "eval-current" not in body:
    sys.exit("smoke_undo: undo does not heal")
if "UNDO workspace=" not in body:
    sys.exit("smoke_undo: heal does not log the workspace")
if "id survives delete" in tx or "一定活过" in tx:
    sys.exit("smoke_undo: undo assumes a snapshot id outlives delete")
ukey = "(define (pad:ux-undo-key!)"
ui = ux.find(ukey)
if ui < 0 or "pad:tx-undo!" not in ux[ui:ux.find("\n(define ", ui + 1)]:
    sys.exit("smoke_undo: byte 26 does not undo")
if '(string=? line "undo")' not in ux:
    sys.exit("smoke_undo: undo is not a sentence")
rkey = "(define (pad:read-undo-page! "
ri = read.find(rkey)
if ri < 0:
    sys.exit("smoke_undo: projection undo is missing")
rj = read.find("\n(define ", ri + 1)
rbody = read[ri:] if rj < 0 else read[ri:rj]
if "set-code" in rbody:
    sys.exit("smoke_undo: projection undo set-code")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SENTENCE=1 \
  "$AURA" "$ROOT/soft/pad/undo_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|TX_UNDO_DISAGREE' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

for line in \
  "CHECK say=helper changed hello" \
  "CHECK who-before=nobody has changed this yet" \
  "CHECK who-kept=the AI helper wrote hello: closer (change 2)" \
  "CHECK undo=undid one keep" \
  "CHECK page=before" \
  "CHECK who-after=nobody has changed this yet" \
  "CHECK author=same" \
  "CHECK set-code=same" \
  "CHECK root=same" \
  "CHECK undo2=nothing to undo" \
  "CHECK page2=before" \
  "CHECK say2=helper changed hello" \
  "CHECK byte=undid one keep" \
  "CHECK byte-page=before" \
  "CHECK byte-who=nobody has changed this yet" \
  "CHECK byte-set-code=same" \
  "UNDO none=1" \
  "UNDO ok=1" \
  "UNDO_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done

python3 - "$OUT/unit.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
kids = [ln.split("=", 1)[1] for ln in lines if ln.startswith("APPLY child=")]
hews = [ln.split("=", 1)[1] for ln in lines if ln.startswith("UNDO workspace=")]
if len(kids) != 2 or len(hews) != 2:
    sys.exit("smoke_undo: expected two keeps and two heals, got %d %d" % (len(kids), len(hews)))
if kids[0] != hews[0] or kids[1] != hews[1]:
    sys.exit("smoke_undo: heal workspace %s is not the file child %s" % (hews, kids))
if any(h in ("0", "-1", "") for h in hews):
    sys.exit("smoke_undo: heal ran on the root")
# One undo consumes one KEEP. The empty undo prints none and does not heal.
none_at = lines.index("UNDO none=1")
first_ok = lines.index("UNDO ok=1")
if not (first_ok < none_at):
    sys.exit("smoke_undo: the empty undo ran before the first KEEP came back")
PY

echo PAD_UNDO_WHO_OK
