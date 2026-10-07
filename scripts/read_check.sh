#!/usr/bin/env bash
# Step 7. Check one page in a child workspace.
# run_soft.sh is the acceptance runner (it defaults the type gate to hard).
# Without docker, the same file runs on the native aura with that gate.
# Prints PAD_READ_CHECK_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/read-check"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/read.aura" "$ROOT/soft/pad/read_test.aura" "$ROOT/soft/pad/play.aura"

python3 - "$ROOT/soft/pad/read.aura" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
i = src.find("(define (pad:read-src ")
j = src.find("\n(define ", i + 1)
body = src[i:j]
if "pad-nb-rows" in body or "pad:ws-source" in body:
    print("read_check: page source still carries notebook rows", file=sys.stderr)
    sys.exit(1)
if "(number? c)" not in src or "(pad:read-id? c)" not in src:
    print("read_check: child id is not accepted with number?", file=sys.stderr)
    sys.exit(1)
PY

fail() { echo "read_check: $*" >&2; exit 1; }

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
  echo "read_check: native hard gate" >&2
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$aura" "$ROOT/soft/pad/read_test.aura"
}

if docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
  bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/read_test.aura \
    >"$OUT/check.txt" 2>"$OUT/check.err" || { cat "$OUT/check.err" >&2; exit 1; }
else
  run_native >"$OUT/check.txt" 2>"$OUT/check.err" || { cat "$OUT/check.err" >&2; exit 1; }
fi

if grep -qiE 'error:|unbound variable|READ_DISAGREE|GAPS define-lookup|GAPS read-leak' \
     "$OUT/check.txt" "$OUT/check.err"; then
  fail "Soft error or leak"
fi
for line in \
  "CHECK id0=true" \
  "CHECK set_delta=1" \
  "CHECK eval_delta=1" \
  "CHECK status=checked" \
  "CHECK root=same" \
  "CHECK canary=a,b" \
  "CHECK q-sane=true" \
  "CHECK stub_set_delta=1" \
  "CHECK stub_eval_delta=0" \
  "CHECK say_same=true" \
  "CHECK child_gone=true" \
  "READ state=checked"
do
  grep -qx "$line" "$OUT/check.txt" || fail "missing $line"
done
grep -q '^READ child=' "$OUT/check.txt" || fail "missing child id"
grep -q '^READ set_code=1 eval=1 ' "$OUT/check.txt" || fail "stats are not one set-code and one eval"
if grep -q 'pad-nb-rows' "$OUT/check.txt"; then
  fail "notebook rows leaked into the log"
fi
echo PAD_READ_CHECK_OK
