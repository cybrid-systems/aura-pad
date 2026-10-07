#!/usr/bin/env bash
# Step 15. The first edit after a check marks the meaning cache stale.
# The insert does not set-code and does not ask query:dirty-nodes.
# Prints PAD_STALE_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/read-stale"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/ux.aura" "$ROOT/soft/pad/read.aura" \
  "$ROOT/soft/pad/read_stale_test.aura"

python3 - "$ROOT/soft/pad/ux.aura" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
i = src.find("(define (pad:ux-insert!")
j = src.find("\n(define ", i + 1)
body = src[i:j if j > 0 else len(src)]
if "query:dirty-nodes" in body or "set-code" in body or "pad:read-check!" in body:
    sys.exit("read_stale: insert calls the engine")
if "check again to ask aura" not in body or '"stale"' not in body:
    sys.exit("read_stale: insert does not mark the cache stale")
PY

fail() { echo "read_stale: $*" >&2; exit 1; }

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
  echo "read_stale: native hard gate" >&2
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$aura" "$ROOT/soft/pad/read_stale_test.aura"
}

if docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
  bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/read_stale_test.aura \
    >"$OUT/off.txt" 2>"$OUT/off.err" || { cat "$OUT/off.err" >&2; exit 1; }
  PAD_SENTENCE=1 bash "$ROOT/scripts/run_soft.sh" \
    /workspace/aura-pad/soft/pad/read_stale_test.aura \
    >"$OUT/on.txt" 2>"$OUT/on.err" || { cat "$OUT/on.err" >&2; exit 1; }
else
  run_native >"$OUT/off.txt" 2>"$OUT/off.err" || { cat "$OUT/off.err" >&2; exit 1; }
  PAD_SENTENCE=1 run_native >"$OUT/on.txt" 2>"$OUT/on.err" \
    || { cat "$OUT/on.err" >&2; exit 1; }
fi

if grep -qiE 'error:|unbound variable|GAPS read-leak|GAPS define-lookup|GAPS query:calls' \
     "$OUT/off.txt" "$OUT/off.err" "$OUT/on.txt" "$OUT/on.err"; then
  fail "Soft error"
fi
grep -qx 'CHECK off_set=0' "$OUT/off.txt" || fail "flag off set-code"
grep -qx 'CHECK off_status=none' "$OUT/off.txt" || fail "flag off marked stale"
for line in \
  "CHECK flag=on" \
  "CHECK status=stale" \
  "CHECK say=check again to ask aura" \
  "CHECK set=0" \
  "CHECK src=changed"
do
  grep -qx "$line" "$OUT/on.txt" || fail "missing $line"
done
echo PAD_STALE_OK
