#!/usr/bin/env bash
# Step 47. Enter on the lower score does not write the page.
# Does not call docker. Prints PAD_TX_WORSE_OK.
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
  echo "smoke_tx_worse: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/tx-worse"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/play_in.aura" \
  "$ROOT/soft/pad/worse_tx_test.aura"

fail() { echo "smoke_tx_worse: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
play = (root / "soft/pad/play_in.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/worse_tx_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test:
        sys.exit("smoke_tx_worse: test contains " + banned)
if play.count("(define *tx-pair*") != 1:
    sys.exit("smoke_tx_worse: pair flag is not defined once")
if "(define *tx-pair*" in tx:
    sys.exit("smoke_tx_worse: tx redefines the pair flag")

def body(src, name):
    key = "(define (" + name
    a = src.find(key)
    if a < 0:
        sys.exit("smoke_tx_worse: missing " + name)
    b = src.find("\n(define ", a + 1)
    return src[a:] if b < 0 else src[a:b]

act = body(tx, "pad:tx-pair-act!")
text = body(tx, "pad:tx-pair-text!")
raise_ = body(tx, "pad:tx-pair-raise!")
if "pad:tx-world-race!" not in text:
    sys.exit("smoke_tx_worse: the card does not use the host scores")
if "pad:tx-card-show!" in text or "pad:tx-card-show!" in raise_:
    sys.exit("smoke_tx_worse: the three-item show resets the mark")
if "pad:tx-card-say!" not in raise_ and "pad:tx-card-at!" not in raise_:
    sys.exit("smoke_tx_worse: the higher score is not marked")
if "(> mine other)" not in act or "that one is not better" not in act:
    sys.exit("smoke_tx_worse: the lower score is not refused")
if act.count("pad:tx-card-keep!") != 1:
    sys.exit("smoke_tx_worse: keep is not the one splice")
for banned in ("pad:proj-splice", "set-code", "ast:snapshot",
               "string-split", "string-trim", "string-replace",
               "force"):
    if banned in act or banned in text or banned in raise_:
        sys.exit("smoke_tx_worse: pair path uses " + banned)
byte = body(tx, "pad:tx-card-byte!")
if "pad:tx-card-act!" not in byte or "force" in byte:
    sys.exit("smoke_tx_worse: confirm is not the card act")
PY

run_one() {
  local dest="$1"
  shift
  env -u PAD_SENTENCE -u PAD_CLASSIC "$@" \
    AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/worse_tx_test.aura" >"$dest" 2>"$dest.err" \
    || { cat "$dest.err" >&2; exit 1; }
  if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
      "$dest" "$dest.err"; then
    cat "$dest" "$dest.err" >&2
    fail "soft error in $dest"
  fi
}

run_one "$OUT/classic.txt" PAD_CLASSIC=1 \
  WORSE_BEFORE="$OUT/classic-worse-before" \
  WORSE_READY="$OUT/classic-worse-ready" \
  WORSE_AFTER="$OUT/classic-worse-after" \
  HIGH_BEFORE="$OUT/classic-high-before" \
  HIGH_READY="$OUT/classic-high-ready" \
  HIGH_AFTER="$OUT/classic-high-after" \
  REV_BEFORE="$OUT/classic-rev-before" \
  REV_READY="$OUT/classic-rev-ready" \
  REV_AFTER="$OUT/classic-rev-after"
run_one "$OUT/sentence.txt" PAD_SENTENCE=1 \
  WORSE_BEFORE="$OUT/sentence-worse-before" \
  WORSE_READY="$OUT/sentence-worse-ready" \
  WORSE_AFTER="$OUT/sentence-worse-after" \
  HIGH_BEFORE="$OUT/sentence-high-before" \
  HIGH_READY="$OUT/sentence-high-ready" \
  HIGH_AFTER="$OUT/sentence-high-after" \
  REV_BEFORE="$OUT/sentence-rev-before" \
  REV_READY="$OUT/sentence-rev-ready" \
  REV_AFTER="$OUT/sentence-rev-after"

for mode in classic sentence; do
  cmp -s "$OUT/$mode-worse-before" "$OUT/$mode-worse-ready" \
    || fail "$mode move changed the projection"
  cmp -s "$OUT/$mode-worse-ready" "$OUT/$mode-worse-after" \
    || fail "$mode lower score changed the projection"
  cmp -s "$OUT/$mode-high-before" "$OUT/$mode-high-ready" \
    || fail "$mode card changed the projection before confirm"
  cmp -s "$OUT/$mode-high-before" "$OUT/$mode-high-after" \
    && fail "$mode higher score left the projection unchanged"
  cmp -s "$OUT/$mode-rev-before" "$OUT/$mode-rev-ready" \
    || fail "$mode reversed card changed the projection"
  cmp -s "$OUT/$mode-rev-before" "$OUT/$mode-rev-after" \
    && fail "$mode reversed higher score left the projection unchanged"
  if [[ ! -s "$OUT/$mode-worse-before" ]]; then
    fail "$mode empty projection"
  fi
done

python3 - "$OUT/classic.txt" "$OUT/sentence.txt" <<'PY'
import sys
classic = open(sys.argv[1], encoding="utf-8").read().splitlines()
sentence = open(sys.argv[2], encoding="utf-8").read().splitlines()

def between(lines, a, b):
    ma, mb = "MARK " + a, "MARK " + b
    if ma not in lines or mb not in lines:
        sys.exit("smoke_tx_worse: missing mark " + a + " " + b)
    ia, ib = lines.index(ma), lines.index(mb)
    if ib <= ia:
        sys.exit("smoke_tx_worse: marks out of order " + a)
    return lines[ia + 1:ib]

def need(part, line):
    if line not in part:
        sys.exit("smoke_tx_worse: missing " + line)

def forbid(part, line):
    if line in part:
        sys.exit("smoke_tx_worse: unexpected " + line)

def scenario(lines, tag):
    ready = between(lines, "low-start", "low-ready")
    moved = between(lines, "low-ready", "low-moved")
    low = between(lines, "low-moved", "low")
    high_ready = between(lines, "high-start", "high-ready")
    high = between(lines, "high-ready", "high")
    rev_ready = between(lines, "rev-start", "rev-ready")
    rev = between(lines, "rev-ready", "rev")
    need(ready, "CHECK low-ready say=> a   b")
    need(ready, "CHECK low-ready card=on")
    need(ready, "CHECK low-ready page=same")
    need(ready, "SCORE a=1")
    need(ready, "SCORE b=0")
    need(ready, "CARD show=1")
    need(ready, "CARD at=0")
    forbid(ready, "CARD keep=1")
    need(moved, "CHECK low-moved say=a   > b")
    need(moved, "CHECK low-moved card=on")
    need(moved, "CHECK low-moved page=same")
    forbid(moved, "BLAST names=")
    forbid(moved, "CARD keep=1")
    need(low, "CHECK low say=that one is not better")
    need(low, "CHECK low card=off")
    need(low, "CHECK low page=same")
    need(low, "CHECK low comment=yes")
    need(low, "CHECK low old=yes")
    need(low, "CHECK low plus2=no")
    need(low, "CHECK low plus0=no")
    need(low, "CHECK low main=yes")
    forbid(low, "CARD keep=1")
    need(high_ready, "CHECK high-ready say=> a   b")
    need(high_ready, "CARD at=0")
    forbid(high_ready, "CARD keep=1")
    need(high, "CHECK high say=kept")
    need(high, "CHECK high page=moved")
    need(high, "CHECK high card=off")
    need(high, "CHECK high comment=yes")
    need(high, "CHECK high old=no")
    need(high, "CHECK high plus2=yes")
    need(high, "CHECK high plus0=no")
    need(high, "CHECK high main=yes")
    need(high, "CARD keep=1")
    need(rev_ready, "CHECK rev-ready say=a   > b")
    need(rev_ready, "SCORE a=0")
    need(rev_ready, "SCORE b=1")
    need(rev_ready, "CARD at=1")
    forbid(rev_ready, "CARD keep=1")
    need(rev, "CHECK rev say=kept")
    need(rev, "CHECK rev page=moved")
    need(rev, "CHECK rev plus2=yes")
    need(rev, "CHECK rev plus0=no")
    need(rev, "CHECK rev old=no")
    need(rev, "CHECK rev comment=yes")
    need(rev, "CHECK rev main=yes")
    need(rev, "CARD keep=1")
    if tag == "classic":
        need(lines, "WORSE_CLASSIC_OK")
        if not any(ln == "CHECK ux-keys=0" for ln in lines):
            sys.exit("smoke_tx_worse: classic used the sentence key")
    else:
        need(lines, "WORSE_SENTENCE_OK")
        keys = [ln for ln in lines if ln.startswith("CHECK ux-keys=")]
        if keys != ["CHECK ux-keys=4"]:
            sys.exit("smoke_tx_worse: sentence keys " + repr(keys))

scenario(classic, "classic")
scenario(sentence, "sentence")
PY

echo PAD_TX_WORSE_OK
