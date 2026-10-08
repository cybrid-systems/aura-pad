#!/usr/bin/env bash
# Step 45. A blast sentence before KEEP. Does not call docker.
# Prints PAD_TX_BLAST_OK.
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
  echo "smoke_tx_blast: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/tx-blast"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/play_in.aura" \
  "$ROOT/soft/pad/blast_tx_test.aura" \
  "$ROOT/soft/pad/m21_test.aura"

fail() { echo "smoke_tx_blast: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
blast = (root / "soft/pad/blast.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/blast_tx_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test:
        sys.exit("smoke_tx_blast: test contains " + banned)

def body(src, name):
    key = "(define (" + name
    a = src.find(key)
    if a < 0:
        sys.exit("smoke_tx_blast: missing " + name)
    b = src.find("\n(define ", a + 1)
    return src[a:] if b < 0 else src[a:b]

take = body(tx, "pad:tx-blast-take! ")
if "query:calls" not in body(tx, "pad:tx-call-n "):
    sys.exit("smoke_tx_blast: the count does not ask query:calls")
if "query:dirty-nodes" not in body(tx, "pad:tx-name-dirty? "):
    sys.exit("smoke_tx_blast: names are not checked with dirty nodes")
if "pad:blast-sites" not in body(tx, "pad:tx-blast-rows ") or \
   "pad:blast-eng-calls" not in body(tx, "pad:tx-blast-rows "):
    sys.exit("smoke_tx_blast: blast.aura is not used")
if "pad:tx-blast-take!" not in take:
    sys.exit("smoke_tx_blast: missing the blast step")
say = body(blast, "pad:blast-say ")
if "changing " not in say or "touches" in blast:
    sys.exit("smoke_tx_blast: the M11 sentence changed")
for rel in ("soft/pad/play_in.aura", "soft/pad/ux.aura", "soft/pad/vi.aura",
            "soft/pad/keys.aura", "soft/pad/play.aura"):
    src = (root / rel).read_text(encoding="utf-8")
    if "query:calls" in src:
        sys.exit("smoke_tx_blast: key file calls query:calls " + rel)
for name, src in (
    ("pad:tx-card-step! ", tx),
    ("pad:tx-card-arrow! ", tx),
    ("pad:tx-card-byte! ", tx),
    ("pad:play-step! ", (root / "soft/pad/play_in.aura").read_text(encoding="utf-8")),
    ("pad:ux-key! ", (root / "soft/pad/ux.aura").read_text(encoding="utf-8")),
    ("pad:vi-type! ", (root / "soft/pad/vi.aura").read_text(encoding="utf-8")),
):
    part = body(src, name)
    if "query:calls" in part or "query:dirty-nodes" in part:
        sys.exit("smoke_tx_blast: arrow path queries " + name)
PY

run_one() {
  local dest="$1"
  shift
  env -u PAD_SENTENCE -u PAD_CLASSIC "$@" \
    AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/blast_tx_test.aura" >"$dest" 2>"$dest.err" \
    || { cat "$dest.err" >&2; exit 1; }
  if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
      "$dest" "$dest.err"; then
    cat "$dest" "$dest.err" >&2
    fail "soft error in $dest"
  fi
}

run_one "$OUT/classic.txt" PAD_CLASSIC=1 \
  BLAST_ARROW_BEFORE="$OUT/classic-arrow-before" \
  BLAST_ARROW_AFTER="$OUT/classic-arrow-after" \
  BLAST_KEEP_BEFORE="$OUT/classic-keep-before" \
  BLAST_KEEP_AFTER="$OUT/classic-keep-after" \
  BLAST_BAD_BEFORE="$OUT/classic-bad-before" \
  BLAST_BAD_AFTER="$OUT/classic-bad-after"
run_one "$OUT/sentence.txt" PAD_SENTENCE=1 \
  BLAST_ARROW_BEFORE="$OUT/sentence-arrow-before" \
  BLAST_ARROW_AFTER="$OUT/sentence-arrow-after" \
  BLAST_KEEP_BEFORE="$OUT/sentence-keep-before" \
  BLAST_KEEP_AFTER="$OUT/sentence-keep-after" \
  BLAST_BAD_BEFORE="$OUT/sentence-bad-before" \
  BLAST_BAD_AFTER="$OUT/sentence-bad-after"

for mode in classic sentence; do
  cmp -s "$OUT/$mode-arrow-before" "$OUT/$mode-arrow-after" \
    || fail "$mode arrow changed the projection"
  cmp -s "$OUT/$mode-bad-before" "$OUT/$mode-bad-after" \
    || fail "$mode disagree changed the projection"
  cmp -s "$OUT/$mode-keep-before" "$OUT/$mode-keep-after" \
    && fail "$mode keep left the projection unchanged"
done

python3 - "$OUT/classic.txt" "$OUT/sentence.txt" <<'PY'
import sys
classic = open(sys.argv[1], encoding="utf-8").read().splitlines()
sentence = open(sys.argv[2], encoding="utf-8").read().splitlines()

def between(lines, a, b):
    ma, mb = "MARK " + a, "MARK " + b
    if ma not in lines or mb not in lines:
        sys.exit("smoke_tx_blast: missing mark " + a + " " + b)
    ia, ib = lines.index(ma), lines.index(mb)
    if ib <= ia:
        sys.exit("smoke_tx_blast: marks out of order " + a)
    return lines[ia + 1:ib]

def need(part, line):
    if line not in part:
        sys.exit("smoke_tx_blast: missing " + line)

def forbid(part, line):
    if line in part:
        sys.exit("smoke_tx_blast: unexpected " + line)

def scenario(lines, tag):
    arrow = between(lines, "arrow-start", "arrow")
    keep = between(lines, "keep-start", "keep")
    bad = between(lines, "bad-start", "bad")
    need(arrow, "CHECK arrow-ready say=touches hello")
    need(arrow, "CHECK arrow-ready card=on")
    need(arrow, "CHECK arrow-ready page=same")
    need(arrow, "CHECK arrow page=same")
    need(arrow, "BLAST names=hello calls=1/1")
    if sum(1 for ln in arrow if ln.startswith("BLAST names=")) != 1:
        sys.exit("smoke_tx_blast: arrow queried again")
    forbid(arrow, "TX_DISAGREE")
    need(keep, "CHECK keep-ready say=touches hello")
    need(keep, "CHECK keep-ready page=same")
    need(keep, "CHECK keep say=kept")
    need(keep, "CHECK keep page=moved")
    need(keep, "CHECK keep comment=yes")
    need(keep, "CHECK keep old=no")
    need(keep, "CHECK keep new=yes")
    need(keep, "CHECK keep main=yes")
    need(keep, "BLAST names=hello calls=1/1")
    need(keep, "CARD keep=1")
    forbid(keep, "TX_DISAGREE")
    need(bad, "CHECK bad-ready say=TX_DISAGREE")
    need(bad, "CHECK bad-ready page=same")
    need(bad, "CHECK bad say=TX_DISAGREE")
    need(bad, "CHECK bad page=same")
    need(bad, "CHECK bad old=yes")
    need(bad, "CHECK bad new=no")
    need(bad, "BLAST names=hello calls=2/1")
    need(bad, "TX_DISAGREE")
    forbid(bad, "CARD keep=1")
    forbid(bad, "CHECK bad say=kept")

if "BLAST_CLASSIC_OK" not in classic:
    sys.exit("smoke_tx_blast: classic marker missing")
if "BLAST_SENTENCE_OK" in classic:
    sys.exit("smoke_tx_blast: classic ran the sentence branch")
if "CHECK ux-keys=0" not in classic:
    sys.exit("smoke_tx_blast: classic called the sentence key")
scenario(classic, "classic")

if "BLAST_SENTENCE_OK" not in sentence:
    sys.exit("smoke_tx_blast: sentence marker missing")
if "BLAST_CLASSIC_OK" in sentence:
    sys.exit("smoke_tx_blast: sentence ran the classic branch")
if "CHECK ux-keys=0" in sentence:
    sys.exit("smoke_tx_blast: sentence did not use its key")
scenario(sentence, "sentence")
PY

echo PAD_TX_BLAST_OK
