#!/usr/bin/env bash
# Step 41. Draw the proposal card and drive it from classic keys.
# Does not call docker. Prints PAD_TX_CARD_OK.
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
  echo "smoke_card: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/card"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/vi.aura" \
  "$ROOT/soft/pad/play_in.aura" \
  "$ROOT/soft/pad/card_test.aura"

fail() { echo "smoke_card: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
vi = (root / "soft/pad/vi.aura").read_text(encoding="utf-8")
play = (root / "soft/pad/play_in.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/card_test.aura").read_text(encoding="utf-8")
em = (root / "soft/pad/emacs.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test or banned in tx[tx.find("(define (pad:tx-card-say!"):]:
        sys.exit("smoke_card: banned word in the card path")
if tx.count("(define *tx-card*") != 0:
    sys.exit("smoke_card: tx redefines the card index")
if play.count("(define *tx-card*") != 1:
    sys.exit("smoke_card: the card index is not defined once on the key path")
step = play.split("(define (pad:play-step! line)", 1)[1]
if not step.lstrip().startswith("(if (number? *tx-card*)"):
    sys.exit("smoke_card: play-step does not look at the card first")
if "(pad:tx-card-line! line)" not in step[:400]:
    sys.exit("smoke_card: play-step does not hand the line to the card")
body = vi.split("(define (pad:vi-type! b)", 1)[1]
if not body.lstrip().startswith("(if (number? *tx-card*)"):
    sys.exit("smoke_card: vi-type does not look at the card first")
if "(pad:tx-card-byte! b)" not in body[:200]:
    sys.exit("smoke_card: vi-type does not hand the byte to the card")
uk = ux.split("(define (pad:ux-key! line)", 1)[1]
if "*ux-keys*" not in uk[:120] or "(pad:tx-card-ux! line)" not in uk[:400]:
    sys.exit("smoke_card: the sentence key does not count or see the card")
card = tx[tx.find("(define (pad:tx-card-say!"):]
for banned in ("preview:keep", "pad:ux-key!", "pad:proj-splice",
               "(typed-mutate-atomic", "ast:snapshot", "set-code",
               "mutate:atomic-batch", "workspace :merge", "workspace:merge"):
    if banned in card:
        sys.exit("smoke_card: card path uses " + banned)
if "finish this card first" not in card:
    sys.exit("smoke_card: missing the refusal sentence")
n = 0
for p in (root / "soft/pad").glob("*.aura"):
    n += p.read_text(encoding="utf-8").count("preview:keep")
if n != 5:
    sys.exit("smoke_card: preview:keep count " + str(n))
cmds = em.split("(define *em-cmds*", 1)[1].split("(define (pad:em-hit?", 1)[0]
if '"preview:keep"' not in cmds or '"preview:undo"' not in cmds:
    sys.exit("smoke_card: *em-cmds* changed")
PY

run_one() {
  local dest="$1"
  shift
  env -u PAD_SENTENCE -u PAD_CLASSIC "$@" \
    AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/card_test.aura" >"$dest" 2>"$dest.err" \
    || { cat "$dest.err" >&2; exit 1; }
  if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
      "$dest" "$dest.err"; then
    cat "$dest" "$dest.err" >&2
    fail "soft error in $dest"
  fi
}

run_one "$OUT/classic.txt" PAD_CLASSIC=1
run_one "$OUT/sentence.txt" PAD_SENTENCE=1

python3 - "$OUT/classic.txt" "$OUT/sentence.txt" <<'PY'
import sys
classic = open(sys.argv[1], encoding="utf-8").read().splitlines()
sentence = open(sys.argv[2], encoding="utf-8").read().splitlines()

def between(lines, a, b):
    ma, mb = "MARK " + a, "MARK " + b
    if ma not in lines or mb not in lines:
        sys.exit("smoke_card: missing mark " + a + " " + b)
    ia, ib = lines.index(ma), lines.index(mb)
    if ib <= ia:
        sys.exit("smoke_card: marks out of order " + a)
    return lines[ia + 1:ib]

def fields(part, tag):
    prefix = "CHECK " + tag + " "
    got = {}
    for ln in part:
        if ln.startswith(prefix):
            k, v = ln[len(prefix):].split("=", 1)
            got[k] = v
    return got

def need(got, tag, **kw):
    for k, v in kw.items():
        if got.get(k) != v:
            sys.exit("smoke_card: " + tag + " " + k + "=" + str(got.get(k))
                     + " want " + str(v))

def one_gt(say, tag):
    if say.count(">") != 1:
        sys.exit("smoke_card: " + tag + " arrows " + say)
    for w in ("keep", "drop", "undo"):
        if w not in say:
            sys.exit("smoke_card: " + tag + " missing " + w)

def check(lines, tag, **kw):
    # fields live in the part that ends at this mark; caller passes them
    need(fields(lines, tag), tag, **kw)

# --- classic: no pad:ux-key! ---
if classic.count("CHECK ux-keys=0") != 2:
    sys.exit("smoke_card: classic called pad:ux-key!")
if "CARD_CLASSIC_OK" not in classic:
    sys.exit("smoke_card: classic marker missing")
if "CARD_SENTENCE_OK" in classic:
    sys.exit("smoke_card: classic ran the sentence branch")

boot = between(classic, "boot", "down")
check(boot, "boot", card="off", col="0", row="0", page="same", mode="normal")
down = between(classic, "down", "up")
check(down, "down", card="off", col="0", row="1", page="same", mode="normal")
up = between(classic, "up", "moved")
check(up, "up", card="off", col="0", row="0", page="same")
moved = between(classic, "moved", "show")
check(moved, "moved", card="off", col="1", row="0", page="same")
show = between(classic, "show", "hjkl")
check(show, "show", say="> keep   drop   undo", card="on",
      col="1", row="0", page="same", mode="normal")
one_gt(fields(show, "show")["say"], "show")
if "CARD show=1" not in moved:
    sys.exit("smoke_card: card was not shown")
hjkl = between(classic, "hjkl", "tab1")
check(hjkl, "hjkl", say="finish this card first", card="on",
      col="1", row="0", page="same", mode="normal")
if show.count("CARD block=1") != 4:
    sys.exit("smoke_card: hjkl block count")
tab1 = between(classic, "tab1", "tab2")
check(tab1, "tab1", say="keep   > drop   undo", card="on",
      col="1", row="0", page="same")
one_gt(fields(tab1, "tab1")["say"], "tab1")
tab2 = between(classic, "tab2", "tab3")
check(tab2, "tab2", say="keep   drop   > undo", card="on", page="same", col="1")
one_gt(fields(tab2, "tab2")["say"], "tab2")
tab3 = between(classic, "tab3", "keep")
check(tab3, "tab3", say="> keep   drop   undo", card="on", page="same", col="1")
if "CARD did=keep" not in tab3:
    sys.exit("smoke_card: byte 13 did not run keep")
keep = between(classic, "keep", "again")
check(keep, "keep", say="did keep", card="off", col="1", row="0", page="same")
again = between(classic, "again", "drop")
check(again, "again", card="off", col="0", row="0", page="same", mode="normal")
if fields(again, "again").get("say") == "finish this card first":
    sys.exit("smoke_card: h still blocked after the card closed")
drop = between(classic, "drop", "esc")
check(drop, "drop", say="did drop", card="off", page="same", col="0")
if "CARD did=drop" not in between(classic, "again", "drop"):
    sys.exit("smoke_card: byte 13 did not run drop")
esc = between(classic, "esc", "free")
check(esc, "esc", say="dropped", card="off", page="same", col="0", row="0")
if "CARD drop=1" not in between(classic, "drop", "esc"):
    sys.exit("smoke_card: byte 27 did not drop")
free = between(classic, "free", "typed")
check(free, "free", card="off", col="1", row="0", page="same")
typed = between(classic, "typed", "blocked-type")
if "CHECK line=x" not in typed:
    sys.exit("smoke_card: vi-type did not take the letter")
blocked = between(classic, "blocked-type", "undo")
if "CHECK line=x" not in blocked:
    sys.exit("smoke_card: vi-type appended while the card was up")
check(blocked, "blocked-type", say="finish this card first", card="on", page="same")
undo = between(classic, "undo", "end")
check(undo, "undo", say="nothing to undo", card="off", page="same", col="1")
if "CARD did=undo" not in blocked or "UNDO none=1" not in blocked:
    sys.exit("smoke_card: byte 13 did not run undo")

# --- sentence arrows ---
if "CARD_SENTENCE_OK" not in sentence:
    sys.exit("smoke_card: sentence marker missing")
if "CARD_CLASSIC_OK" in sentence:
    sys.exit("smoke_card: sentence ran the classic branch")
if "CHECK ux-keys=0" in sentence:
    sys.exit("smoke_card: sentence arrows did not enter pad:ux-key!")
s0 = between(sentence, "s0", "s1")
check(s0, "s0", say="> keep   drop   undo", card="on", col="0", row="0", page="same")
one_gt(fields(s0, "s0")["say"], "s0")
s1 = between(sentence, "s1", "s2")
check(s1, "s1", say="keep   > drop   undo", card="on", col="0", page="same")
s2 = between(sentence, "s2", "s3")
check(s2, "s2", say="keep   drop   > undo", card="on", col="0", page="same")
s3 = between(sentence, "s3", "s4")
check(s3, "s3", say="keep   > drop   undo", card="on", col="0", page="same")
s4 = between(sentence, "s4", "s5")
check(s4, "s4", say="> keep   drop   undo", card="on", col="0", page="same")
s5 = between(sentence, "s5", "s6")
check(s5, "s5", say="keep   > drop   undo", card="on", col="0", page="same")
s6 = between(sentence, "s6", "sh")
check(s6, "s6", say="keep   drop   > undo", card="on", col="0", page="same")
sh = between(sentence, "sh", "sb")
check(sh, "sh", say="finish this card first", card="on", col="0", row="0", page="same")
sb = between(sentence, "sb", "sact")
check(sb, "sb", say="finish this card first", card="on", col="0", page="same")
sact = between(sentence, "sact", "sdrop")
check(sact, "sact", say="nothing to undo", card="off", col="0", page="same")
if "CARD did=undo" not in sb:
    sys.exit("smoke_card: sentence enter did not run the marked item")
sdrop = between(sentence, "sdrop", "end")
check(sdrop, "sdrop", say="dropped", card="off", col="0", row="0", page="same")
if "CARD drop=1" not in between(sentence, "sact", "sdrop"):
    sys.exit("smoke_card: sentence esc did not drop")
PY

echo PAD_TX_CARD_OK
