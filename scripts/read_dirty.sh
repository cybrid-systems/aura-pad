#!/usr/bin/env bash
# Step 22. The next check reports query:dirty-nodes.
# A body edit names the define. A comment edit says nothing is dirty.
# Unbound prints GAPS query:dirty-nodes and the check fails.
# The dirty set is not a reason to skip set-code.
# run_soft.sh is the acceptance runner. Without docker, native aura uses
# the same hard type gate. Prints PAD_DIRTY_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/read-dirty"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/read.aura" "$ROOT/soft/pad/read_dirty_test.aura" \
  "$ROOT/soft/pad/ux.aura"

python3 - "$ROOT/soft/pad/read.aura" "$ROOT/soft/pad/ux.aura" <<'PY'
import sys
rd, ux = sys.argv[1:]
src = open(rd, encoding="utf-8").read()
uxs = open(ux, encoding="utf-8").read()

def body(text, name):
    key = "(define (" + name
    i = text.find(key)
    if i < 0:
        sys.exit("read_dirty: missing " + name)
    j = text.find("\n(define ", i + 1)
    if j < 0:
        j = len(text)
    return text[i:j]

for banned in ("string-split", "string-trim", "string-replace"):
    if banned in src:
        sys.exit("read_dirty: read.aura contains " + banned)
sw = body(src, "pad:read-switched! ")
if "pad:ws-set-code!" not in sw or "pad:ws-eval!" not in sw:
    sys.exit("read_dirty: check skipped set-code or eval")
if sw.find("pad:read-ask!") < sw.find("pad:ws-eval!"):
    sys.exit("read_dirty: dirty ask runs before eval")
if "GAPS query:dirty-nodes" not in src or "query:dirty-nodes" not in src:
    sys.exit("read_dirty: dirty report is missing")
ins = body(uxs, "pad:ux-insert! ")
if "query:dirty-nodes" in ins.split("\n", 1)[-1]:
    sys.exit("read_dirty: insert calls query:dirty-nodes")
PY

fail() { echo "read_dirty: $*" >&2; exit 1; }

run_native() {
  local aura="${AURA_BIN:-}"
  if [[ -z "$aura" || ! -x "$aura" ]]; then
    for c in /workspace/aura-grok/build-release/aura \
             "$HOME/code/grok-dev/aura-grok/build-release/aura" \
             /home/dev/code/grok-dev/aura-grok/build-release/aura \
             /workspace/aura-grok/build/aura \
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
  echo "read_dirty: native hard gate" >&2
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$aura" "$ROOT/soft/pad/read_dirty_test.aura"
}

if docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
  bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/read_dirty_test.aura \
    >"$OUT/dirty.txt" 2>"$OUT/dirty.err" || { cat "$OUT/dirty.err" >&2; exit 1; }
else
  run_native >"$OUT/dirty.txt" 2>"$OUT/dirty.err" || { cat "$OUT/dirty.err" >&2; exit 1; }
fi

if grep -qiE 'error:|unbound variable|READ_DISAGREE|GAPS define-lookup|GAPS read-leak|GAPS query:calls' \
     "$OUT/dirty.txt" "$OUT/dirty.err"; then
  fail "Soft error or leak"
fi
gaps=$(grep -c 'GAPS query:dirty-nodes' "$OUT/dirty.txt" || true)
if [[ "$gaps" != "1" ]]; then
  fail "expected one GAPS query:dirty-nodes line, saw $gaps"
fi
for line in \
  "CHECK lam=(lambda (x) (+ x 1))" \
  "CHECK lam_same=true" \
  "CHECK lam2=(lambda (x) (+ x 2))" \
  "CHECK fresh_status=checked" \
  "CHECK fresh_set=1" \
  "CHECK fresh_eval=1" \
  "CHECK fresh_kept=same" \
  "CHECK comment_status=checked" \
  "CHECK comment_set=1" \
  "CHECK comment_eval=1" \
  "CHECK comment_say=nothing is dirty" \
  "CHECK comment_note=kept" \
  "CHECK comment_ids=none" \
  "CHECK body_status=checked" \
  "CHECK body_set=1" \
  "CHECK body_eval=1" \
  "CHECK body_say=hello is dirty" \
  "CHECK body_note=kept" \
  "CHECK gap_status=fail" \
  "CHECK root=same" \
  "CHECK child_gone=true"
do
  grep -qx "$line" "$OUT/dirty.txt" || fail "missing $line"
done
python3 - "$OUT/dirty.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read().splitlines()
lines = [ln for ln in text if ln.startswith("READ query:dirty-nodes=")]
if len(lines) < 3:
    sys.exit("read_dirty: missing dirty id logs")
body = lines[2].split("=", 1)[1]
if body == "none" or not any(ch.isdigit() for ch in body):
    sys.exit("read_dirty: body log has no id: " + lines[2])
if lines[0].split("=", 1)[1] != "none" or lines[1].split("=", 1)[1] != "none":
    sys.exit("read_dirty: fresh or comment log is not none")
PY
if grep -q 'pad-nb-rows' "$OUT/dirty.txt"; then
  fail "notebook rows leaked into the log"
fi
echo PAD_DIRTY_OK
