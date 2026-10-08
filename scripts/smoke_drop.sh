#!/usr/bin/env bash
# Step 34. A type error and a human reject leave the projection and the
# sidecar alone. Failure is restore, not another set-code.
# Does not call docker. Prints PAD_DROP_CLEAN_OK.
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
  echo "smoke_drop: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/drop"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/drop_test.aura"

fail() { echo "smoke_drop: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/drop_test.aura").read_text(encoding="utf-8")
typed = (root / "soft/pad/fixtures/drop-type").read_text(encoding="utf-8")
human = (root / "soft/pad/fixtures/drop-human").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in tx or banned in test:
        sys.exit("smoke_drop: banned text " + banned)
if "workspace :merge" in tx or "workspace:merge" in tx:
    sys.exit("smoke_drop: merge is called")
key = "(define (pad:tx-fail! "
i = tx.find(key)
if i < 0:
    sys.exit("smoke_drop: missing pad:tx-fail!")
j = tx.find("\n(define ", i + 1)
body = tx[i:] if j < 0 else tx[i:j]
if "set-code" in body:
    sys.exit("smoke_drop: failure path set-code")
if "ast:restore" not in body or "eval-current" not in body:
    sys.exit("smoke_drop: failure path does not restore")
if "DROP workspace=" not in body:
    sys.exit("smoke_drop: heal does not log the workspace")
if "pad:read-aw!" in body or "serialize-workspace" in body:
    sys.exit("smoke_drop: failure path writes a sidecar")
if 'pad:tx-fail! c snap "type"' not in tx or 'pad:tx-fail! c snap "human"' not in tx:
    sys.exit("smoke_drop: type and human do not share the restore path")
if "reject" not in human or "(lambda" not in human:
    sys.exit("smoke_drop: human fixture is not a rejected op")
if "(lambda" not in typed or "reject" in typed:
    sys.exit("smoke_drop: type fixture is not one op")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_SENTENCE=1 AURA_PAD_AW_FILE="$OUT/page.aura" \
  "$AURA" "$ROOT/soft/pad/drop_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|TX_UNDO_DISAGREE|AW wrote|APPLY splice|workspace :merge|workspace:merge' \
    "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error or a write on DROP"
fi

for line in \
  "DROP reason=type" \
  "DROP reason=human" \
  "DROP restore=1" \
  "APPLY set-code" \
  "APPLY typed-mutate-atomic=no" \
  "APPLY typed-mutate-atomic=ok" \
  "CHECK say-type=aura cannot change this page yet" \
  "CHECK say-human=aura cannot change this page yet" \
  "CHECK page-type=same" \
  "CHECK page-human=same" \
  "CHECK proj-type=same" \
  "CHECK proj-human=same" \
  "CHECK set-code=same" \
  "CHECK root=same" \
  "CHECK undo=nothing to undo" \
  "CHECK undo-page=same" \
  "CHECK aw=none" \
  "CHECK proj-file=none" \
  "UNDO none=1" \
  "DROP_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done

if [[ -e "$OUT/page.aura" || -e "$OUT/page.aura.aw" ]]; then
  fail "DROP created a sidecar"
fi

python3 - "$OUT/unit.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
def all_of(prefix):
    return [ln.split("=", 1)[1] for ln in lines if ln.startswith(prefix)]
children = all_of("APPLY child=")
drops = all_of("DROP workspace=")
if children != drops or len(children) != 2:
    sys.exit("smoke_drop: child " + ",".join(children) + " drop " + ",".join(drops))
for n in children:
    if n in ("", "0", "-1") or not n.lstrip("-").isdigit():
        sys.exit("smoke_drop: bad workspace " + n)
if lines.count("APPLY set-code") != 2:
    sys.exit("smoke_drop: set-code count")
if lines.count("DROP restore=1") != 2:
    sys.exit("smoke_drop: restore count")
def first(prefix, start=0):
    for i in range(start, len(lines)):
        if lines[i].startswith(prefix):
            return i
    sys.exit("smoke_drop: missing " + prefix)
t_no = first("APPLY typed-mutate-atomic=no")
t_why = first("DROP reason=type")
t_ok = first("DROP restore=1", t_why)
h_ok = first("APPLY typed-mutate-atomic=ok", t_ok)
h_why = first("DROP reason=human", h_ok)
h_back = first("DROP restore=1", h_why)
if not (t_no < t_why < t_ok < h_ok < h_why < h_back):
    sys.exit("smoke_drop: order")
if "APPLY splice" in lines[t_no:h_back]:
    sys.exit("smoke_drop: splice on a drop")
PY
echo "PAD_DROP_CLEAN_OK"
