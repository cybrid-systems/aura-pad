#!/usr/bin/env bash
# Step 8. Empty sentence Enter shows cached engine meaning.
# used 0 is accepted. Four arrows do not set-code.
# run_soft.sh is the acceptance runner. Without docker, native aura uses
# the same hard type gate. Prints PAD_READ_SAY_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/read-say"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/ux.aura" "$ROOT/soft/pad/read.aura" \
  "$ROOT/soft/pad/read_say_test.aura"

python3 - "$ROOT/soft/pad/ux.aura" "$ROOT/soft/pad/read.aura" <<'PY'
import sys
ux, rd = sys.argv[1:]
uxs = open(ux, encoding="utf-8").read()
rds = open(rd, encoding="utf-8").read()
if "pad:say-run!" not in uxs or "pad:ux-say-at" not in uxs:
    sys.exit("read_say: sentence enter is missing")
if "define-lookup" in open(ux, encoding="utf-8").read().split("define (pad:ux-say-at)")[1].split("\n(define ")[0]:
    sys.exit("read_say: arrow path calls define-lookup")
body = uxs.split("define (pad:ux-arrow!")[1].split("\n(define ")[0]
if "set-code" in body or "pad:read-check!" in body:
    sys.exit("read_say: arrows check again")
if "*read-mean*" not in rds:
    sys.exit("read_say: check does not keep a meaning cache")
PY

fail() { echo "read_say: $*" >&2; exit 1; }

run_native() {
  local aura="${AURA_BIN:-}"
  if [[ -z "$aura" || ! -x "$aura" ]]; then
    for c in /workspace/aura-grok/build/aura \
             "$HOME/code/grok-dev/aura-grok/build/aura" \
             /home/dev/code/grok-dev/aura-grok/build/aura; do
      if [[ -x "$c" ]]; then aura="$c"; break; fi
    done
  fi
  [[ -n "${aura:-}" && -x "$aura" ]] || return 1
  local lib
  lib="$(cd "$(dirname "$aura")/.." && pwd)/lib"
  if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
    lib=/workspace/aura-grok/lib
  fi
  echo "read_say: native hard gate" >&2
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$@" "$aura" "$ROOT/soft/pad/read_say_test.aura"
}

if docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
  runner=(bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/read_say_test.aura)
else
  runner=(run_native)
fi

"${runner[@]}" >"$OUT/off.txt" 2>"$OUT/off.err" || { cat "$OUT/off.err" >&2; exit 1; }
PAD_SENTENCE=1 "${runner[@]}" >"$OUT/on.txt" 2>"$OUT/on.err" || { cat "$OUT/on.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|READ_DISAGREE|GAPS define-lookup|GAPS read-leak' \
     "$OUT/off.txt" "$OUT/off.err" "$OUT/on.txt" "$OUT/on.err"; then
  fail "Soft error or leak"
fi
grep -qx 'CHECK off_set=0' "$OUT/off.txt" || fail "flag off still checked"
grep -qx 'CHECK off_say=same' "$OUT/off.txt" || fail "flag off changed SAY"
grep -qx 'CHECK flag=on' "$OUT/on.txt" || fail "flag on did not run"
grep -qx 'CHECK hello_status=checked' "$OUT/on.txt" || fail "hello was not checked"
grep -qx 'CHECK hello_set=1' "$OUT/on.txt" || fail "hello check was not one set-code"
grep -qx 'CHECK hello_src=same' "$OUT/on.txt" || fail "hello projection changed"
grep -qx 'CHECK hello_arrows=0' "$OUT/on.txt" || fail "arrows set-code"
grep -qx 'CHECK hello_kept=yes' "$OUT/on.txt" || fail "arrows rewrote SAY"
grep -qx 'CHECK alias_status=checked' "$OUT/on.txt" || fail "alias was not checked"
grep -qx 'CHECK alias_set=1' "$OUT/on.txt" || fail "alias check was not one set-code"
grep -qx 'CHECK alias_arrows=0' "$OUT/on.txt" || fail "alias arrows set-code"
grep -qx 'CHECK alias_uses=0' "$OUT/on.txt" || fail "alias uses is not 0"
python3 - "$OUT/on.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read().splitlines()
say = [ln for ln in text if ln.startswith("CHECK hello_say=")]
uses = [ln for ln in text if ln.startswith("CHECK hello_uses=")]
refs = [ln for ln in text if ln.startswith("CHECK hello_refs=")]
alias = [ln for ln in text if ln.startswith("CHECK alias_say=")]
if len(say) != 1 or len(uses) != 1 or len(refs) != 1 or len(alias) != 1:
    sys.exit("read_say: missing SAY lines")
hello = say[0].split("=", 1)[1]
n = uses[0].split("=", 1)[1]
r = refs[0].split("=", 1)[1]
if "born line" not in hello or ("used " + n) not in hello or r not in hello:
    sys.exit("read_say: hello SAY is not the ref-count sentence: " + hello)
a = alias[0].split("=", 1)[1]
if "used 0" not in a or "born line" not in a:
    sys.exit("read_say: alias SAY rejected used 0: " + a)
PY
echo PAD_READ_SAY_OK
