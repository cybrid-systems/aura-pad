#!/usr/bin/env bash
# Step 28. apply FIXTURE keeps one define and does not open the network.
# PAD_LIVE=0 and PAD_LIVE=1 take the same path. Does not call docker.
# Prints PAD_APPLY_OK.
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
  echo "smoke_apply: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/apply"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/apply_test.aura"

fail() { echo "smoke_apply: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/apply_test.aura").read_text(encoding="utf-8")
fix = (root / "soft/pad/fixtures/keep-hello").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in tx or banned in test:
        sys.exit("smoke_apply: new file contains " + banned)
if "hello=(lambda (x) (+ x 2))" not in fix:
    sys.exit("smoke_apply: fixture is not one op")
if "http" in tx or "pad:ai-set-text!" in tx:
    sys.exit("smoke_apply: apply reaches the network or the model writer")
if "pad:tx-snap!" not in tx or "pad:proj-splice!" not in tx:
    sys.exit("smoke_apply: path is missing snap or splice")
if "typed-mutate-atomic" not in tx or "pad:tx-gate" not in tx:
    sys.exit("smoke_apply: path is missing the gate or the batch")
if 'TITLE snapshot restore left pad:play-cmd! invalid' not in tx:
    sys.exit("smoke_apply: missing the aura issue title")
key = "(define (pad:ux-apply! "
i = ux.find(key)
if i < 0:
    sys.exit("smoke_apply: sentence does not apply")
j = ux.find("\n(define ", i + 1)
body = ux[i:] if j < 0 else ux[i:j]
if "pad:ai-set-text!" in body or "http" in body:
    sys.exit("smoke_apply: sentence apply calls the model writer")
PY

run_one() {
  local live="$1" dest="$2"
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    PAD_SENTENCE=1 PAD_LIVE="$live" \
    "$AURA" "$ROOT/soft/pad/apply_test.aura" >"$dest" 2>"$dest.err" \
    || { cat "$dest.err" >&2; exit 1; }
  if grep -qiE 'error:|unbound variable|GAPS snapshot-heal' "$dest" "$dest.err"; then
    cat "$dest" "$dest.err" >&2
    fail "live=$live soft error"
  fi
}

run_one 0 "$OUT/off.txt"
run_one 1 "$OUT/on.txt"

for dest in "$OUT/off.txt" "$OUT/on.txt"; do
  for line in \
    "APPLY net=0" \
    "APPLY set-code" \
    "APPLY gate=ok" \
    "APPLY typed-mutate-atomic=ok" \
    "APPLY play-cmd=ok" \
    "APPLY splice" \
    "CHECK say=helper changed hello" \
    "CHECK comment=same" \
    "CHECK body=new" \
    "CHECK old=gone" \
    "CHECK proj=page" \
    "CHECK later=aura cannot change this page yet" \
    "CHECK later-page=same" \
    "APPLY_UNIT_OK"
  do
    grep -qx "$line" "$dest" || fail "missing $line in $dest"
  done
  if grep -q 'http' "$dest"; then
    fail "log mentions http"
  fi
done
grep -qx 'APPLY live=0' "$OUT/off.txt" || fail "live 0 was not logged"
grep -qx 'APPLY live=1' "$OUT/on.txt" || fail "live 1 was not logged"

python3 - "$OUT/off.txt" "$OUT/on.txt" <<'PY'
import sys
for path in sys.argv[1:]:
    lines = open(path, encoding="utf-8").read().splitlines()
    def first(prefix):
        for i, ln in enumerate(lines):
            if ln.startswith(prefix):
                return i
        sys.exit("smoke_apply: missing " + prefix + " in " + path)
    code = first("APPLY set-code")
    gate = first("APPLY gate=")
    ws = first("APPLY workspace=")
    snap = first("APPLY snap=")
    fp = first("APPLY mutate:set-agent-fingerprint=42")
    batch = first("APPLY typed-mutate-atomic=ok")
    back = first("APPLY mutate:set-agent-fingerprint=1")
    probe = first("APPLY play-cmd=")
    wrote = first("APPLY splice")
    child = first("APPLY child=")
    if not (code < gate < ws < snap < probe < fp < batch < back < wrote):
        sys.exit("smoke_apply: order " + path)
    if lines[child].split("=", 1)[1] != lines[ws].split("=", 1)[1]:
        sys.exit("smoke_apply: snap was not on the file child")
    n = lines[snap].split("=", 1)[1]
    if not n.isdigit():
        sys.exit("smoke_apply: snap id is not a number")
PY
echo "PAD_APPLY_OK"
