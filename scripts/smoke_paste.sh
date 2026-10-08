#!/usr/bin/env bash
# Step 37. A sentence proposal does not paste model text.
# Classic rewrite still writes the page. Does not call docker.
# Prints PAD_NO_PASTE_OK.
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
  echo "smoke_paste: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/paste"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/ai.aura" \
  "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/paste_test.aura"

fail() { echo "smoke_paste: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
ai = (root / "soft/pad/ai.aura").read_text(encoding="utf-8")
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/paste_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in ai or banned in ux or banned in test:
        sys.exit("smoke_paste: banned text " + banned)
if "pad:ai-set-text!" in ux:
    sys.exit("smoke_paste: sentence file names the model writer")
if "(pad:ux-propose!" not in ux:
    sys.exit("smoke_paste: unknown sentence does not go through the proposal")
key = "(define (pad:ai-set-text! "
i = ai.find(key)
if i < 0:
    sys.exit("smoke_paste: missing the model writer")
j = ai.find("\n(define ", i + 1)
body = ai[i:] if j < 0 else ai[i:j]
if "*ai-sets*" not in body:
    sys.exit("smoke_paste: the writer has no counter")
rk = "(define (pad:ai-rewrite! "
ri = ai.find(rk)
if ri < 0:
    sys.exit("smoke_paste: missing rewrite")
rj = ai.find("\n(define ", ri + 1)
rewrite = ai[ri:] if rj < 0 else ai[ri:rj]
if "pad:ai-sentence?" not in rewrite:
    sys.exit("smoke_paste: rewrite ignores the sentence flag")
if rewrite.count("pad:ai-set-text!") != 1:
    sys.exit("smoke_paste: rewrite call count " + str(rewrite.count("pad:ai-set-text!")))
# The call sits in the flag-off arm. The refusal sentence is the other arm.
call = rewrite.find("pad:ai-set-text!")
flag = rewrite.find("pad:ai-sentence?")
if call < flag:
    sys.exit("smoke_paste: rewrite pastes before it reads the flag")
PY

run_aura() {
  local dest="$1"
  shift
  env -u PAD_SENTENCE "$@" \
    AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/paste_test.aura" >"$dest" 2>"$dest.err" \
    || { cat "$dest.err" >&2; exit 1; }
  if grep -qiE 'error:|unbound variable' "$dest" "$dest.err"; then
    cat "$dest" "$dest.err" >&2
    fail "soft error in $dest"
  fi
}

run_aura "$OUT/sentence.txt" PAD_SENTENCE=1
run_aura "$OUT/classic.txt"

for line in \
  "CHECK say-later=aura cannot change this page yet" \
  "CHECK later-sets=0" \
  "CHECK later-page=same" \
  "CHECK later-ux=same" \
  "CHECK later-line=clear" \
  "CHECK say-rewrite=aura cannot change this page yet" \
  "CHECK rewrite-do=vi-do" \
  "CHECK rewrite-sets=0" \
  "CHECK rewrite-page=same" \
  "PASTE_SENTENCE_OK"
do
  grep -qx "$line" "$OUT/sentence.txt" || fail "sentence missing $line"
done

if grep -q 'pad:ai-set-text!' "$OUT/sentence.txt" "$OUT/sentence.txt.err"; then
  fail "sentence log names the model writer"
fi

for line in \
  "CHECK classic-do=vi-do" \
  "CHECK say-classic=the chat rewrote this page. press u to put yours back" \
  "CHECK classic-sets=1" \
  "CHECK classic-page=wrote" \
  "PASTE_CLASSIC_OK"
do
  grep -qx "$line" "$OUT/classic.txt" || fail "classic missing $line"
done

echo PAD_NO_PASTE_OK
