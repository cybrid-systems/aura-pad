#!/usr/bin/env bash
# Step 42. One fixture proposal in sentence mode and classic mode.
# Esc leaves the projection and writes no sidecar. Enter keeps only
# when the score is strictly higher. Does not call docker.
# Prints PAD_M21_OK.
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
  echo "smoke_m21: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/m21"
rm -rf "$OUT"
mkdir -p "$OUT"
AW="$OUT/should-not.aw"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/ai.aura" \
  "$ROOT/soft/pad/play_in.aura" \
  "$ROOT/soft/pad/m21_test.aura"

fail() { echo "smoke_m21: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
doc = (root / "docs/m21.md").read_text(encoding="utf-8")
for need in ("PAD_M21_OK", "PAD_CLASSIC=1", "M-x rewrite", "pad:tx-propose!",
             "pad:ai-set-text!", ";; keep this", "byte 27", "byte 13",
             "does not call docker", "propose_ok.txt",
             "that one is not better", "finish this card first"):
    if need not in doc:
        sys.exit("smoke_m21: doc missing " + need)
ai = (root / "soft/pad/ai.aura").read_text(encoding="utf-8")
rk = "(define (pad:ai-rewrite! "
ri = ai.find(rk)
if ri < 0:
    sys.exit("smoke_m21: missing rewrite")
rj = ai.find("\n(define ", ri + 1)
rewrite = ai[ri:] if rj < 0 else ai[ri:rj]
if "pad:ai-classic?" not in rewrite or "pad:tx-propose!" not in rewrite:
    sys.exit("smoke_m21: classic rewrite does not enter the proposal")
if rewrite.find("pad:ai-classic?") > rewrite.find("pad:tx-propose!"):
    sys.exit("smoke_m21: propose runs before the classic flag")
if rewrite.count("pad:ai-set-text!") != 1:
    sys.exit("smoke_m21: rewrite call count")
call = rewrite.find("pad:ai-set-text!")
flag = rewrite.find("pad:ai-sentence?")
if flag < 0 or call < flag:
    sys.exit("smoke_m21: rewrite pastes before the sentence flag")
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
prop = tx[tx.find("(define (pad:tx-propose-text! "):]
for banned in ("string-split", "string-trim", "string-replace",
               "ast:snapshot", "(typed-mutate-atomic", "mutate:atomic-batch",
               "workspace :merge", "workspace:merge", "set-code"):
    if banned in prop:
        sys.exit("smoke_m21: proposal path uses " + banned)
if "PROPOSE net=0" not in prop or "propose_ok.txt" not in tx:
    sys.exit("smoke_m21: fixture proposal is not offline")
PY

run_one() {
  local dest="$1"
  shift
  env -u PAD_SENTENCE -u PAD_CLASSIC "$@" \
    AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    AURA_PAD_AW_FILE="$AW" \
    "$AURA" "$ROOT/soft/pad/m21_test.aura" >"$dest" 2>"$dest.err" \
    || { cat "$dest.err" >&2; exit 1; }
  if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
      "$dest" "$dest.err"; then
    cat "$dest" "$dest.err" >&2
    fail "soft error in $dest"
  fi
  if grep -q 'http' "$dest" "$dest.err"; then
    fail "network word in $dest"
  fi
  if grep -q 'pad:ai-set-text!' "$dest" "$dest.err"; then
    fail "model writer named in $dest"
  fi
  if [[ -e "$AW" ]]; then
    fail "sidecar was written"
  fi
}

run_one "$OUT/classic.txt" PAD_CLASSIC=1 \
  M21_BEFORE="$OUT/classic-before" M21_AFTER="$OUT/classic-after"
run_one "$OUT/sentence.txt" PAD_SENTENCE=1 \
  M21_BEFORE="$OUT/sentence-before" M21_AFTER="$OUT/sentence-after"

cmp -s "$OUT/classic-before" "$OUT/classic-after" \
  || fail "classic esc changed the projection"
cmp -s "$OUT/sentence-before" "$OUT/sentence-after" \
  || fail "sentence esc changed the projection"
if [[ ! -s "$OUT/classic-before" || ! -s "$OUT/sentence-before" ]]; then
  fail "empty projection"
fi

python3 - "$OUT/classic.txt" "$OUT/sentence.txt" <<'PY'
import sys
classic = open(sys.argv[1], encoding="utf-8").read().splitlines()
sentence = open(sys.argv[2], encoding="utf-8").read().splitlines()

def between(lines, a, b):
    ma, mb = "MARK " + a, "MARK " + b
    if ma not in lines or mb not in lines:
        sys.exit("smoke_m21: missing mark " + a + " " + b)
    ia, ib = lines.index(ma), lines.index(mb)
    if ib <= ia:
        sys.exit("smoke_m21: marks out of order " + a)
    return lines[ia + 1:ib]

def need_line(part, line):
    if line not in part:
        sys.exit("smoke_m21: missing " + line)

def need_log(part, line):
    if line not in part:
        sys.exit("smoke_m21: missing log " + line)

def forbid(part, line):
    if line in part:
        sys.exit("smoke_m21: unexpected " + line)

ready = (
    "CHECK esc-ready say=> keep   drop   undo",
    "CHECK esc-ready card=on",
    "CHECK esc-ready page=same",
    "CHECK esc-ready buf=page",
    "CHECK esc-ready sets=0",
    "CHECK esc-ready comment=yes",
    "CHECK esc-ready old=yes",
    "CHECK esc-ready new=no",
    "CHECK esc-ready main=yes",
)
esc = (
    "CHECK esc say=dropped",
    "CHECK esc card=off",
    "CHECK esc page=same",
    "CHECK esc buf=page",
    "CHECK esc sets=0",
    "CHECK esc comment=yes",
    "CHECK esc old=yes",
    "CHECK esc new=no",
    "CHECK esc main=yes",
)
keep = (
    "CHECK keep say=kept",
    "CHECK keep card=off",
    "CHECK keep page=moved",
    "CHECK keep buf=page",
    "CHECK keep sets=0",
    "CHECK keep comment=yes",
    "CHECK keep old=no",
    "CHECK keep new=yes",
    "CHECK keep main=yes",
)
same = (
    "CHECK same say=that one is not better",
    "CHECK same card=off",
    "CHECK same page=same",
    "CHECK same buf=page",
    "CHECK same sets=0",
    "CHECK same comment=yes",
    "CHECK same old=yes",
    "CHECK same new=no",
    "CHECK same main=yes",
)

def scenario(lines, tag):
    esc_part = between(lines, "esc-start", "esc")
    keep_part = between(lines, "keep-start", "keep")
    same_part = between(lines, "same-start", "same")
    for line in ready:
        need_line(esc_part, line)
    for line in esc:
        need_line(lines, line)
    for line in keep:
        need_line(lines, line)
    for line in same:
        need_line(lines, line)
    for line in ("PROPOSE enter=1", "PROPOSE net=0", "PROPOSE kind=tried",
                 "SCORE page=0", "SCORE child=1", "SCORE better=yes",
                 "SCORE exec=2", "CARD drop=1"):
        need_log(esc_part, line)
    forbid(esc_part, "CARD keep=1")
    for line in ("PROPOSE kind=tried", "SCORE page=0", "SCORE child=1",
                 "SCORE better=yes", "SCORE exec=2", "CARD did=keep",
                 "CARD keep=1"):
        need_log(keep_part, line)
    for line in ("PROPOSE kind=tried", "SCORE page=1", "SCORE child=1",
                 "SCORE better=no", "SCORE exec=2", "CARD did=keep"):
        need_log(same_part, line)
    forbid(same_part, "CARD keep=1")
    forbid(same_part, "SCORE better=yes")

if "CARD_CLASSIC_OK" not in classic:
    sys.exit("smoke_m21: classic marker missing")
if "CARD_SENTENCE_OK" in classic:
    sys.exit("smoke_m21: classic ran the sentence branch")
if "CHECK rewrite=vi-do" not in classic:
    sys.exit("smoke_m21: classic rewrite did not return vi-do")
if "CHECK ux-keys=0" not in classic:
    sys.exit("smoke_m21: classic called the sentence key")
scenario(classic, "classic")

if "CARD_SENTENCE_OK" not in sentence:
    sys.exit("smoke_m21: sentence marker missing")
if "CARD_CLASSIC_OK" in sentence:
    sys.exit("smoke_m21: sentence ran the classic branch")
if any(ln.startswith("CHECK rewrite=") for ln in sentence):
    sys.exit("smoke_m21: sentence called rewrite")
scenario(sentence, "sentence")
PY

echo PAD_M21_OK
