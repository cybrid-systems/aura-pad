#!/usr/bin/env bash
# Step 14. Log engine names against Soft names.
# A non-empty diff does not fail the check and does not change the projection.
# run_soft.sh is the acceptance runner. Without docker, native aura uses
# the same hard type gate. Prints PAD_READ_DIFF_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/read-diff"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/read.aura" "$ROOT/soft/pad/read_diff_test.aura" \
  "$ROOT/soft/pad/read_test.aura"

python3 - "$ROOT/soft/pad/read.aura" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()

def body(name):
    key = "(define (" + name
    i = src.find(key)
    if i < 0:
        sys.exit("read_diff: missing " + name)
    j = src.find("\n(define ", i + 1)
    if j < 0:
        j = len(src)
    return src[i:j]

diff = body("pad:read-diff ")
log = body("pad:read-log-diff! ")
for need in ("pad:ws-soft-defs", "pad:ws-engine-defs", "pad:ws-diff"):
    if need not in diff:
        sys.exit("read_diff: name diff does not use " + need)
for banned in ("pad:ws-check!", "pad:ws-load!", "pad:ws-source", "*pl-say*"):
    if banned in diff or banned in log:
        sys.exit("read_diff: diff path contains " + banned)
if 'READ missing=' not in log or 'READ extra=' not in log:
    sys.exit("read_diff: log lines are not missing= and extra=")
PY

fail() { echo "read_diff: $*" >&2; exit 1; }

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
  echo "read_diff: native hard gate" >&2
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$aura" "$ROOT/soft/pad/read_diff_test.aura"
}

if docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
  bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/read_diff_test.aura \
    >"$OUT/diff.txt" 2>"$OUT/diff.err" || { cat "$OUT/diff.err" >&2; exit 1; }
else
  run_native >"$OUT/diff.txt" 2>"$OUT/diff.err" || { cat "$OUT/diff.err" >&2; exit 1; }
fi

if grep -qiE 'error:|unbound variable|READ_DISAGREE|GAPS define-lookup|GAPS read-leak' \
     "$OUT/diff.txt" "$OUT/diff.err"; then
  fail "Soft error or leak"
fi
for line in \
  "DIFF flat" \
  "READ missing=none" \
  "READ extra=none" \
  "CHECK flat_status=checked" \
  "CHECK flat_src=same" \
  "CHECK flat_say=same" \
  "CHECK flat_set=1" \
  "CHECK flat_missing=none" \
  "CHECK flat_extra=none" \
  "DIFF note" \
  "READ extra=hello" \
  "CHECK note_status=checked" \
  "CHECK note_src=same" \
  "CHECK note_say=same" \
  "CHECK note_set=1" \
  "CHECK note_missing=none" \
  "CHECK note_extra=hello" \
  "CHECK root=same" \
  "CHECK child_gone=true"
do
  grep -qx "$line" "$OUT/diff.txt" || fail "missing $line"
done
if grep -q 'pad-nb-rows' "$OUT/diff.txt"; then
  fail "notebook rows leaked into the log"
fi
# The note page's extra name stays in the log. SAY is the unchanged word.
if grep -qx 'CHECK note_say=changed' "$OUT/diff.txt"; then
  fail "SAY lists names"
fi
echo PAD_READ_DIFF_OK
