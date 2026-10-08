#!/usr/bin/env bash
# Step 39. One proposal is one typed batch in a file child.
# The heal is pad:tx-snap!. A type failure leaves the projection.
# Does not call docker. Prints PAD_TX_APPLY_OK.
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
  echo "smoke_batch: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/batch"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/robot.aura" \
  "$ROOT/soft/pad/world.aura" \
  "$ROOT/soft/pad/batch_test.aura"

fail() { echo "smoke_batch: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
robot = (root / "soft/pad/robot.aura").read_text(encoding="utf-8")
world = (root / "soft/pad/world.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/batch_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test:
        sys.exit("smoke_batch: test contains " + banned)
a = tx.find("(define *tx-robot*")
if a < 0 or "(define (pad:tx-run! " not in tx[a:]:
    sys.exit("smoke_batch: missing the proposal runner")
body = tx[a:]
for banned in ("mutate:atomic-batch", "workspace :merge", "workspace:merge",
               "ast:snapshot", "string-split", "string-trim", "string-replace"):
    if banned in body:
        sys.exit("smoke_batch: run path uses " + banned)
if "pad:tx-snap!" not in body or "pad:world-batch!" not in body:
    sys.exit("smoke_batch: run path does not use the child batch and the old heal")
if "pad:robot-tx-sexprs" not in body:
    sys.exit("smoke_batch: run path does not use the robot forms")
if "(typed-mutate-atomic" in body:
    sys.exit("smoke_batch: run path calls the batch itself")
wb = world.find("(define (pad:world-batch! ")
if wb < 0:
    sys.exit("smoke_batch: missing pad:world-batch!")
wbody = world[wb:]
if wbody.count("typed-mutate-atomic") != 1:
    sys.exit("smoke_batch: world batch count " + str(wbody.count("typed-mutate-atomic")))
for banned in ("mutate:atomic-batch", "workspace :merge", "workspace:merge"):
    if banned in wbody:
        sys.exit("smoke_batch: world batch uses " + banned)
wo = world.find("(define (pad:world-open! ")
if wo < 0 or "number?" not in world[wo:wb]:
    sys.exit("smoke_batch: child id is not tested with number?")
rb = robot.find("(define (pad:robot-tx-sexprs ")
if rb < 0 or "pad:robot-sexprs" not in robot[rb:rb + 200]:
    sys.exit("smoke_batch: robot does not build the proposal forms")
PY

run_aura() {
  local dest="$1"
  shift
  env "$@" \
    AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/batch_test.aura" >"$dest" 2>"$dest.err" \
    || { cat "$dest.err" >&2; exit 1; }
  if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|mutate:atomic-batch|workspace :merge|workspace:merge' \
      "$dest" "$dest.err"; then
    cat "$dest" "$dest.err" >&2
    fail "soft error in $dest"
  fi
}

run_aura "$OUT/hard.txt" AURA_MUTATE_TYPE_GATE=hard
run_aura "$OUT/soft.txt" AURA_MUTATE_TYPE_GATE=soft

python3 - "$OUT/hard.txt" "$OUT/soft.txt" <<'PY'
import sys
hard = open(sys.argv[1], encoding="utf-8").read().splitlines()
soft = open(sys.argv[2], encoding="utf-8").read().splitlines()

def between(lines, a, b):
    if a not in lines or b not in lines:
        sys.exit("smoke_batch: missing mark " + a + " " + b)
    return lines[lines.index(a) + 1:lines.index(b)]

def need(lines, exact):
    if exact not in lines:
        sys.exit("smoke_batch: missing " + exact)

def count(lines, exact):
    return sum(1 for ln in lines if ln == exact)

def prefix(lines, p):
    return [ln for ln in lines if ln.startswith(p)]

gate = between(hard, "MARK gate", "MARK bad")
bad = between(hard, "MARK bad", "MARK ok")
ok = between(hard, "MARK ok", "MARK two")
two = between(hard, "MARK two", "MARK end")

for part in (gate, bad, ok, two):
    if any("GAPS" in ln for ln in part):
        sys.exit("smoke_batch: hard path printed GAPS")
    if any(ln.startswith("APPLY splice") for ln in part):
        sys.exit("smoke_batch: proposal spliced the page")

need(gate, "CHECK gate kind=DROP")
need(gate, "APPLY gate=too-many")
need(gate, "CHECK gate page=same")
need(gate, "CHECK gate code=same")
need(gate, "CHECK gate canary=a,b")
need(gate, "CHECK gate sane=yes")
if prefix(gate, "APPLY snap=") or prefix(gate, "APPLY typed-mutate-atomic="):
    sys.exit("smoke_batch: a gate refusal snapped or mutated")

need(bad, "CHECK bad kind=DROP")
need(bad, "DROP reason=type")
need(bad, "DROP restore=1")
need(bad, "APPLY play-cmd=ok")
need(bad, "CHECK bad page=same")
need(bad, "CHECK bad code=same")
need(bad, "CHECK bad canary=a,b")
need(bad, "CHECK bad sane=yes")
if count(bad, "APPLY typed-mutate-atomic=no") != 1 or count(bad, "APPLY typed-mutate-atomic=ok") != 0:
    sys.exit("smoke_batch: bad batch count")
if len(prefix(bad, "APPLY snap=")) != 1:
    sys.exit("smoke_batch: bad heal count")
kids = prefix(bad, "APPLY child=")
if len(kids) != 1 or not kids[0].split("=", 1)[1].isdigit():
    sys.exit("smoke_batch: bad child " + ",".join(kids))

need(ok, "CHECK ok kind=tried")
need(ok, "APPLY tried=1")
need(ok, "APPLY ops=1")
need(ok, "APPLY play-cmd=ok")
need(ok, "CHECK ok page=same")
need(ok, "CHECK ok code=same")
need(ok, "CHECK ok canary=a,b")
need(ok, "CHECK ok sane=yes")
if count(ok, "APPLY typed-mutate-atomic=ok") != 1:
    sys.exit("smoke_batch: ok batch count")
if len(prefix(ok, "APPLY snap=")) != 1:
    sys.exit("smoke_batch: ok heal count")

need(two, "CHECK two kind=tried")
need(two, "APPLY tried=1")
need(two, "APPLY ops=2")
need(two, "CHECK two page=same")
need(two, "CHECK two code=same")
need(two, "CHECK two canary=a,b")
need(two, "CHECK two sane=yes")
if count(two, "APPLY typed-mutate-atomic=ok") != 1:
    sys.exit("smoke_batch: two-op batch count")

if "BATCH_UNIT_OK" not in hard:
    sys.exit("smoke_batch: hard unit did not finish")

need(soft, "GAPS type-gate")
need(soft, "CHECK soft kind=DROP")
need(soft, "CHECK soft page=same")
need(soft, "CHECK soft code=same")
need(soft, "CHECK soft canary=a,b")
need(soft, "CHECK soft sane=yes")
need(soft, "BATCH_UNIT_OK")
if prefix(soft, "APPLY snap=") or prefix(soft, "APPLY typed-mutate-atomic=") or prefix(soft, "APPLY child="):
    sys.exit("smoke_batch: soft gate still mutated")
PY

echo PAD_TX_APPLY_OK
