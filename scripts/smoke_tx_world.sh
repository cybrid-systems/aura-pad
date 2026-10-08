#!/usr/bin/env bash
# Step 44. Two children race when the sentence is submitted.
# fiber_live only when both joins land. Otherwise host-sequential.
# Does not call docker. Does not time the race. Prints PAD_TX_WORLD_OK.
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
  echo "smoke_tx_world: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/tx-world"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/world_tx_test.aura"

fail() { echo "smoke_tx_world: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
rules = (root / "soft/pad/rules.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/world_tx_test.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test:
        sys.exit("smoke_tx_world: test contains " + banned)
a = tx.find("(define (pad:tx-world-race! ")
if a < 0:
    sys.exit("smoke_tx_world: missing the race")
body = tx[a:]
for banned in ("current-time-ms", "faster", "string-split", "string-trim",
               "string-replace", "ast:snapshot", "set-code",
               "(typed-mutate-atomic", "mutate:atomic-batch",
               "workspace :merge", "workspace:merge", "read-line"):
    if banned in body:
        sys.exit("smoke_tx_world: race path uses " + banned)
if "pad:stamp-world!" not in body or "pad:race-thunks!" not in body:
    sys.exit("smoke_tx_world: race does not reuse the world stamp")
for rel in ("soft/pad/play_in.aura", "soft/pad/ux.aura", "soft/pad/vi.aura",
            "soft/pad/keys.aura", "soft/pad/play.aura"):
    src = (root / rel).read_text(encoding="utf-8")
    if "pad:tx-world" in src:
        sys.exit("smoke_tx_world: key path races " + rel)
finish = rules.find("(define (pad:finish-world!)")
if finish < 0 or "fiber_live" not in rules[finish:finish + 400]:
    sys.exit("smoke_tx_world: honesty rule missing")
if "*race-joined*" not in rules[finish:finish + 400]:
    sys.exit("smoke_tx_world: stamp ignores joins")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/world_tx_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

python3 - "$OUT/unit.txt" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
lines = text.splitlines()
for need in ("CHECK one=whole", "CHECK three=refused", "CHECK page=same",
             "SCORE a=1", "SCORE b=0", "RACE a=1", "RACE b=0"):
    if need not in lines:
        sys.exit("smoke_tx_world: missing " + need)
worlds = [ln for ln in lines if ln.startswith("WORLD line=")]
if len(worlds) != 1:
    sys.exit("smoke_tx_world: world lines " + str(len(worlds)))
w = worlds[0]
if "fiber_live" in w:
    if "host-sequential" in w:
        sys.exit("smoke_tx_world: both world lines")
    m = re.search(r"backend=(\d+) joins=2/2", w)
    if not m or int(m.group(1)) <= 0:
        sys.exit("smoke_tx_world: fiber_live without both joins: " + w)
elif not w.startswith("WORLD line=host-sequential"):
    sys.exit("smoke_tx_world: unexpected " + w)
elif "fiber_live" in text:
    sys.exit("smoke_tx_world: fiber_live on the host path")
PY

echo PAD_TX_WORLD_OK
