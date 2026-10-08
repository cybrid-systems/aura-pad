#!/usr/bin/env bash
# Step 26. pad:tx-gate allows kid and 4096. pad:pen-gate still refuses both.
# A banned word or a bad bracket takes no snapshot.
# Does not call docker. Prints PAD_TX_GATE_OK.
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
  echo "smoke_tx: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/tx"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" "$ROOT/soft/pad/tx_test.aura" \
  "$ROOT/soft/pad/pen.aura"

fail() { echo "smoke_tx: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
pen = (root / "soft/pad/pen.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/tx_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in tx or banned in test:
        sys.exit("smoke_tx: new file contains " + banned)
if "pad:tx-gate" not in tx or "pad:why-brackets-ok?" not in tx:
    sys.exit("smoke_tx: gate does not keep the bracket count")
if "*pen-whos*" in tx:
    sys.exit("smoke_tx: tx gate reads the pen who list")
if "4096" not in tx:
    sys.exit("smoke_tx: missing 4096 cap")
if "ast:snapshot" in tx:
    sys.exit("smoke_tx: gate takes a snapshot")
if '(define *pen-max-len* 120)' not in pen:
    sys.exit("smoke_tx: pen max length changed")
if '(define *pen-whos* (list "helper" "macro" "law"))' not in pen:
    sys.exit("smoke_tx: pen who list changed")
if "kid" in pen.split("*pen-whos*", 1)[1].split("\n", 1)[0]:
    sys.exit("smoke_tx: pen who list contains kid")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/tx_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

for line in \
  "CHECK pen-kid=not-allowed" \
  "CHECK pen-max=120" \
  "CHECK pen-whos=helper.macro.law" \
  "CHECK tx-kid=ok" \
  "CHECK tx-helper=ok" \
  "CHECK tx-macro=ok" \
  "CHECK tx-law=ok" \
  "CHECK tx-robot=not-allowed" \
  "CHECK tx-long-n=121" \
  "CHECK tx-long=ok" \
  "CHECK pen-long=too-long" \
  "CHECK tx-cap-n=4096" \
  "CHECK tx-cap=ok" \
  "CHECK tx-over=too-long" \
  "CHECK tx-slack=ok" \
  "CHECK tx-past=too-long" \
  "CHECK tx-mean=not-kind" \
  "CHECK tx-nl=ok" \
  "CHECK tx-ban=not-allowed" \
  "CHECK tx-brackets=brackets" \
  "CHECK snap=0" \
  "CHECK writes=0" \
  "CHECK root-s1=no" \
  "CHECK child-saw=yes" \
  "CHECK pen-born=no-def" \
  "CHECK tx-born=ok" \
  "CHECK tx-unborn=no-def" \
  "CHECK root-after=no" \
  "TX_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
echo "PAD_TX_GATE_OK"
