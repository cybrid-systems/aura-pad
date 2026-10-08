#!/usr/bin/env bash
# Step 53. The kinder fixture rewrites the last sentence.
# An unkind line in that fixture is refused. Does not call docker.
# Prints PAD_STORY_KIND_OK.
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
  echo "smoke_story_kind: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/story-kind"
rm -rf "$OUT"
mkdir -p "$OUT"
PY="$ROOT/scripts/propose_tx.py"
FIX="$ROOT/soft/pad/fixtures/story_kinder.txt"

fail() { echo "smoke_story_kind: $*" >&2; exit 1; }

python3 - "$PY" "$FIX" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
fix = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
if "story_kinder.txt" not in src or "make the last line kinder" not in src:
    sys.exit("smoke_story_kind: the kinder sentence is not selected")
if "urlopen" in src or "http-post" in src or "socket" in src:
    sys.exit("smoke_story_kind: proposer posts")
if "stupid" not in fix:
    sys.exit("smoke_story_kind: the fixture has no unkind word")
if 's3=(lambda () "the cat dreamed")' not in fix:
    sys.exit("smoke_story_kind: the fixture does not rewrite the last line")
PY

env PAD_LIVE=0 python3 "$PY" --two "make the last line kinder" >"$OUT/kind.txt" 2>"$OUT/kind.err" \
  || fail "kinder selection failed"
cmp -s "$OUT/kind.txt" "$FIX" || fail "kinder fixture drifted"

env PAD_LIVE=0 python3 "$PY" --two "make hello closer" >"$OUT/two.txt" 2>"$OUT/two.err" \
  || fail "two-proposal run failed"
cmp -s "$OUT/two.txt" "$ROOT/soft/pad/fixtures/propose_two.txt" || fail "two fixture drifted"

env PAD_LIVE=1 python3 "$PY" --two "make the last line kinder" >"$OUT/live.txt" 2>"$OUT/live.err" \
  && fail "live kinder posted"
if [[ -s "$OUT/live.txt" ]]; then
  fail "live kinder wrote a proposal"
fi

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/story_kind_test.aura" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/story_proj.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
test = (root / "soft/pad/story_kind_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test:
        sys.exit("smoke_story_kind: banned word")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/story_kind_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

python3 - "$OUT/unit.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
got = {}
for ln in lines:
    if ln.startswith("CHECK ") and "=" in ln:
        k, v = ln.split("=", 1)
        got[k[6:]] = v
for need in (
    "CHECK ops=2",
    "CHECK mean-tag=not-kind",
    "CHECK mean-bytes=same",
    "CHECK keep-say=kept",
    "CHECK head=same",
    "CHECK last=kinder",
    "CHECK old-last=moved",
    "CHECK shown=sentences",
):
    if need not in lines:
        sys.exit("smoke_story_kind: missing " + need + "\n" + "\n".join(lines))
say = got.get("mean-say", "")
words = [w for w in say.split(" ") if w]
if len(words) > 8 or "type error" in say:
    sys.exit("smoke_story_kind: mean say is " + say)
if say == "":
    sys.exit("smoke_story_kind: empty mean say")
PY

echo PAD_STORY_KIND_OK
