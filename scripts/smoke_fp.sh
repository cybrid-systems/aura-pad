#!/usr/bin/env bash
# Step 25. A file rebind stamps helper 42, then returns the fingerprint to 1.
# A non-success rebind leaves the page. An unbound stamp fails closed.
# A gate that is not hard does not rebind.
# Does not call docker. Prints PAD_FP_OK.
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
  echo "smoke_fp: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/fp"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/read.aura" "$ROOT/soft/pad/fp_test.aura" \
  "$ROOT/soft/pad/eng_who.aura"

fail() { echo "smoke_fp: $*" >&2; exit 1; }

# The load sits in the lazy helper, and the sentence line does not call it.
if ! grep -q 'eng_who.aura' "$ROOT/soft/pad/read.aura"; then
  fail "read.aura does not load eng_who"
fi
if grep -q 'eng_who' "$ROOT/soft/pad/ux.aura"; then
  fail "sentence line loads eng_who"
fi
if ! grep -q 'GAPS type-gate' "$ROOT/soft/pad/read.aura"; then
  fail "missing type-gate gap"
fi
if ! grep -q 'GAPS mutate:set-agent-fingerprint' "$ROOT/soft/pad/read.aura"; then
  fail "missing fingerprint gap"
fi

run_one() {
  local mode="$1" gate="$2" dest="$3"
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE="$gate" AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    PAD_FP_MODE="$mode" \
    "$AURA" "$ROOT/soft/pad/fp_test.aura" >"$dest" 2>"$dest.err" \
    || { cat "$dest.err" >&2; exit 1; }
  if grep -qiE 'error:|unbound variable|READ_DISAGREE|GAPS define-lookup|GAPS read-leak' \
       "$dest" "$dest.err"; then
    fail "$mode soft error"
  fi
}

run_one ok hard "$OUT/ok.txt"
run_one soft soft "$OUT/soft.txt"

for line in \
  "CHECK fresh_status=checked" \
  "CHECK fresh_set=1" \
  "CHECK fresh_page=same" \
  "CHECK body_status=checked" \
  "CHECK body_set=1" \
  "CHECK body_say=hello is dirty" \
  "CHECK body_page=same" \
  "CHECK body_proj=moved" \
  "CHECK body_proj=src" \
  "CHECK miss_status=fail" \
  "CHECK miss_page=same" \
  "CHECK miss_proj=kept" \
  "CHECK gap_status=fail" \
  "CHECK gap_page=same" \
  "CHECK gap_proj=kept" \
  "CHECK kept_proj=src" \
  "CHECK root=same" \
  "FP_UNIT_OK"
do
  grep -qx "$line" "$OUT/ok.txt" || fail "missing $line"
done

python3 - "$OUT/ok.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
def first(prefix):
    for i, ln in enumerate(lines):
        if ln.startswith(prefix):
            return i
    sys.exit("smoke_fp: missing " + prefix)
stamp = first("READ mutate:set-agent-fingerprint=42")
wrote = first("READ rebind hello")
back = first("READ mutate:set-agent-fingerprint=1")
if not (stamp < wrote < back):
    sys.exit("smoke_fp: stamp order " + str((stamp, wrote, back)))
# The refused rebind still returns the fingerprint to kid, and does not publish.
skip = first("READ rebind-skip hello")
back2 = [i for i, ln in enumerate(lines) if ln == "READ mutate:set-agent-fingerprint=1"]
if len(back2) < 2 or not (skip < back2[1]):
    sys.exit("smoke_fp: refused rebind did not restore kid")
if sum(ln == "GAPS mutate:set-agent-fingerprint" for ln in lines) != 1:
    sys.exit("smoke_fp: expected one unbound stamp")
if any(ln.startswith("READ mutate:set-agent-fingerprint=") for ln in lines[skip + 1:] if ln.endswith("=42")):
    sys.exit("smoke_fp: unbound stamp still wrote helper")
if "GAPS type-gate" in lines:
    sys.exit("smoke_fp: hard run printed type-gate")
PY

for line in \
  "CHECK fresh_status=checked" \
  "CHECK fresh_set=1" \
  "CHECK gate_status=fail" \
  "CHECK gate_set=0" \
  "CHECK gate_page=same" \
  "CHECK gate_proj=kept" \
  "CHECK gate_voice=same" \
  "GAPS type-gate" \
  "CHECK root=same" \
  "FP_UNIT_OK"
do
  grep -qx "$line" "$OUT/soft.txt" || fail "soft missing $line"
done
if grep -q 'READ mutate:set-agent-fingerprint=' "$OUT/soft.txt"; then
  fail "soft gate stamped a fingerprint"
fi
if grep -q 'READ rebind ' "$OUT/soft.txt"; then
  fail "soft gate rebound"
fi
echo "PAD_FP_OK"
