#!/usr/bin/env bash
# Step 40. The same checks score the page and the child.
# A dangerous form is not called. Does not call docker.
# Prints PAD_TX_SCORE_OK.
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
  echo "smoke_score: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/score"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/score_test.aura"

fail() { echo "smoke_score: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/score_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test:
        sys.exit("smoke_score: test contains " + banned)
a = tx.find("(define (pad:tx-call! ")
b = tx.find("(define (pad:tx-check-pass? ")
c = tx.find("(define (pad:tx-scan-ops ")
if a < 0 or b < a or c < 0:
    sys.exit("smoke_score: score helpers are missing")
call = tx[a:b]
if "lam" in call:
    sys.exit("smoke_score: the check call receives the model form")
if "pad:read-guard-src?" not in tx[c:]:
    sys.exit("smoke_score: the scan is not the file guard")
if "pad:tx-form" not in tx[c:c + 400]:
    sys.exit("smoke_score: the scan does not read the form")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/score_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

python3 - "$OUT/unit.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()

def between(a, b):
    if a not in lines or b not in lines:
        sys.exit("smoke_score: missing mark " + a)
    return lines[lines.index(a) + 1:lines.index(b)]

def need(part, exact):
    if exact not in part:
        sys.exit("smoke_score: missing " + exact)

def has_prefix(part, p):
    return any(ln.startswith(p) for ln in part)

marks = ["MARK show", "MARK begin", "MARK let", "MARK nest",
         "MARK up", "MARK same", "MARK lower", "MARK end"]
parts = [between(marks[i], marks[i + 1]) for i in range(len(marks) - 1)]
show, begin, let, nest, up, same, lower = parts

for name, part in (("show", show), ("begin", begin), ("let", let), ("nest", nest)):
    need(part, "CHECK " + name + " kind=no")
    need(part, "SCORE exec=0")
    need(part, "SCORE better=no")
    need(part, "CHECK " + name + " page=same")
    if has_prefix(part, "APPLY typed-mutate-atomic=") or has_prefix(part, "SCORE exec=1") or has_prefix(part, "SCORE exec=2"):
        sys.exit("smoke_score: " + name + " ran a check")

need(up, "CHECK up kind=tried")
need(up, "SCORE page=0")
need(up, "SCORE child=1")
need(up, "SCORE better=yes")
need(up, "SCORE exec=2")
need(up, "CHECK up page=same")
need(up, "APPLY typed-mutate-atomic=ok")

need(same, "CHECK same kind=tried")
need(same, "SCORE page=1")
need(same, "SCORE child=1")
need(same, "SCORE better=no")
need(same, "SCORE exec=2")
need(same, "CHECK same page=same")

need(lower, "CHECK lower kind=tried")
need(lower, "SCORE page=1")
need(lower, "SCORE child=0")
need(lower, "SCORE better=no")
need(lower, "SCORE exec=2")
need(lower, "CHECK lower page=same")

if "SCORE_UNIT_OK" not in lines:
    sys.exit("smoke_score: unit did not finish")
PY

echo PAD_TX_SCORE_OK
