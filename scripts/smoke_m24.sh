#!/usr/bin/env bash
# Step 59 keeps arrows off the rule file and the intend file (PAD_LAZY_RULE_OK).
# Step 60 chains that check with repair, the live rule, Emacs timing, and
# the classic pty. Native aura only. Does not call docker.
# Prints PAD_LAZY_RULE_OK and PAD_M24_OK.
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
  echo "smoke_m24: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/m24"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "smoke_m24: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
doc = (root / "docs/m24.md").read_text(encoding="utf-8")
for need in (
    "PAD_M24_OK",
    "does not call docker",
    "PAD_FX_DEC_OK",
    "PAD_TX_FIX_OK",
    "PAD_NO_EVAL_OK",
    "PAD_RULE_OK",
    "PAD_LAZY_RULE_OK",
    "PAD_PERF_EMACS_OK",
    "CLI_PTY_OK",
    "PAD_CLASSIC=1",
    "try 1",
    "try 2",
    "string-append x 1",
    "(* x 2)",
    "tab 4",
    "heal, tab jumps 4 spaces",
    "changes once",
    "set_code",
    "does not update `docs/tutorial.md`",
    "does not bump the Aura commit",
    "0f93a31ed",
):
    if need not in doc:
        sys.exit("smoke_m24: doc missing " + need)
tut = (root / "docs/tutorial.md").read_text(encoding="utf-8")
if "heal, tab jumps 4 spaces" in tut or "PAD_M24_OK" in tut:
    sys.exit("smoke_m24: tutorial.md was extended")
PY

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/lazy_rule_test.aura" \
  "$ROOT/soft/pad/play.aura" \
  "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/tx.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
play = (root / "soft/pad/play.aura").read_text(encoding="utf-8")
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/lazy_rule_test.aura").read_text(encoding="utf-8")

def body(src, name):
    key = "(define (" + name
    a = src.find(key)
    if a < 0:
        sys.exit("smoke_m24: missing " + name)
    b = src.find("\n(define ", a + 1)
    return src[a:] if b < 0 else src[a:b]

for name in ("fix_loop.aura", "kid_rules.aura"):
    if name in play or name in ux or name in test:
        sys.exit("smoke_m24: load list names " + name)
top = "\n".join(play.splitlines()[:45])
if "fix_loop" in top or "kid_rules" in top:
    sys.exit("smoke_m24: play top loads a late file")
for name in ("pad:ux-arrow! ", "pad:ux-move! ", "pad:ux-key! "):
    part = body(ux, name)
    for banned in ("pad:tx-kr-ready!", "pad:tx-fix", "pad:kr-cmd!", "fix_loop", "kid_rules"):
        if banned in part:
            sys.exit("smoke_m24: " + name + " loads a late file")
if "pad:tx-kr-ready!" not in body(ux, "pad:ux-rule! "):
    sys.exit("smoke_m24: tab does not load the rule file")
if "fix_loop.aura" not in body(tx, "pad:tx-fix-ready!"):
    sys.exit("smoke_m24: repair does not load the intend file")
if "kid_rules.aura" not in body(tx, "pad:tx-kr-ready!)"):
    sys.exit("smoke_m24: the rule loader lost its file")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SENTENCE=1 \
  "$AURA" "$ROOT/soft/pad/lazy_rule_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak|M11_FIX_DISAGREE|M11_RULES_DISAGREE' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi
for line in \
  "CHECK arrows-kr=ok" \
  "CHECK arrows-fx=ok" \
  "CHECK set_code=ok" \
  "set_code=0" \
  "CHECK rules=ok" \
  "CHECK tab-kr=ok" \
  "CHECK tab-fx=ok" \
  "CHECK tab-value=ok" \
  "CHECK hello=ok" \
  "CHECK fix-fx=ok" \
  "CHECK fix-tag=ok" \
  "LAZY_RULE_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done
echo "PAD_LAZY_RULE_OK"

run_marker() {
  local script="$1" marker="$2" dest="$3"
  bash "$ROOT/scripts/$script" >"$dest" 2>"$dest.err" || {
    cat "$dest" "$dest.err" >&2
    fail "$script failed"
  }
  grep -qx "$marker" "$dest" || fail "missing $marker"
  echo "$marker"
}

run_marker smoke_fx_dec.sh PAD_FX_DEC_OK "$OUT/fx.txt"
run_marker smoke_tx_fix.sh PAD_TX_FIX_OK "$OUT/fix.txt"
run_marker smoke_no_eval.sh PAD_NO_EVAL_OK "$OUT/noeval.txt"
run_marker smoke_rule.sh PAD_RULE_OK "$OUT/rule.txt"

run_emacs() {
  unset PAD_SENTENCE
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/emacs_test.aura" >"$OUT/emacs.txt" 2>"$OUT/emacs.err"
  if grep -qiE 'error:|unbound variable' "$OUT/emacs.txt" "$OUT/emacs.err"; then
    cat "$OUT/emacs.err" >&2 || true
    echo "smoke_m24: Soft error in emacs_test" >&2
    exit 1
  fi
  if ! grep -qE '^EMACS_TEST checks=[0-9]+ fail=0$' "$OUT/emacs.txt"; then
    echo "PAD_PERF_EMACS_FAIL (fast path != reference)" >&2
    exit 1
  fi
  grep -q '^PAD_PERF_EMACS_OK$' "$OUT/emacs.txt"
}

echo "smoke_m24: Emacs frame, sentence flag unset"
if ! run_emacs; then
  echo "smoke_m24: emacs retry (wall-clock noise on a shared box)"
  run_emacs || {
    echo "PAD_PERF_EMACS_FAIL (over the 16 ms frame)" >&2
    exit 1
  }
fi
echo "PAD_PERF_EMACS_OK"

command -v cc >/dev/null 2>&1 || fail "host cc missing; not calling docker"
PAD_C_DOCKER=0 bash "$ROOT/scripts/build_c.sh" >"$OUT/build_c.txt"
if grep -q 'docker cc' "$OUT/build_c.txt"; then
  fail "build used docker; stopped"
fi
grep -q 'host cc' "$OUT/build_c.txt" || fail "host cc did not build"
AP="$ROOT/out/c/aura-pad"
[[ -x "$AP" ]] || fail "aura-pad did not build"
mkdir -p "$OUT/pty"
for sc in open new unsaved emergency vi; do
  PAD_CLASSIC=1 AURA_BIN="$AURA" timeout 180 python3 "$ROOT/scripts/cli_pty.py" \
    "$sc" "$OUT/pty/$sc.txt" -- "$AP" "$OUT/pty/$sc.txt" \
    | tee "$OUT/pty_$sc.txt"
  grep -q '^CLI_PTY_OK ' "$OUT/pty_$sc.txt" || fail "classic pty $sc"
done
echo "PAD_M24_OK"
