#!/usr/bin/env bash
# Step 32. A new process opens the same path.
# Engine who matching the save, or an explicit soft-only gap, both pass.
# Does not call docker. Prints PAD_REOPEN_OK.
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
  echo "smoke_reopen: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/reopen"
rm -rf "$OUT"
mkdir -p "$OUT"
FILE="$OUT/page.aura"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/read.aura" \
  "$ROOT/soft/pad/m20_probe.aura"

fail() { echo "smoke_reopen: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
read = (root / "soft/pad/read.aura").read_text(encoding="utf-8")
probe = (root / "soft/pad/m20_probe.aura").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace",
               "pad:time-open!", "pad:book-open!", "std/persist"):
    if banned in read or banned in probe:
        sys.exit("smoke_reopen: banned text " + banned)
key = "(define (pad:read-reopen! "
i = read.find(key)
if i < 0:
    sys.exit("smoke_reopen: missing pad:read-reopen!")
j = read.find("\n(define ", i + 1)
body = read[i:] if j < 0 else read[i:j]
if "deserialize-workspace" not in body:
    sys.exit("smoke_reopen: reopen does not deserialize")
if "pad:time-open!" in body or "pad:book-open!" in body:
    sys.exit("smoke_reopen: reopen uses the book opener")
if "GAPS persist-global" not in read or "soft-only " not in read:
    sys.exit("smoke_reopen: soft-only path is missing")
if "query:code" not in body and "pad:q-code" not in body:
    sys.exit("smoke_reopen: root program is not recorded")
PY

run_phase() {
  local phase="$1" dest="$2"
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    PAD_SENTENCE=1 AURA_PAD_AW_FILE="$FILE" AURA_PAD_REOPEN="$phase" \
    "$AURA" "$ROOT/soft/pad/m20_probe.aura" >"$dest" 2>"$dest.err" \
    || { cat "$dest.err" >&2; exit 1; }
  if grep -qiE 'error:|unbound variable|GAPS snapshot-heal|GAPS read-leak' "$dest" "$dest.err"; then
    cat "$dest" "$dest.err" >&2
    fail "phase=$phase soft error"
  fi
}

run_phase save "$OUT/save.txt"
run_phase open "$OUT/open.txt"

python3 - "$OUT/save.txt" "$OUT/open.txt" <<'PY'
import pathlib, sys
save = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines()
open_ = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace").splitlines()

def one(lines, prefix):
    hit = [ln[len(prefix):] for ln in lines if ln.startswith(prefix)]
    if len(hit) != 1:
        sys.exit("smoke_reopen: wanted one " + prefix + " got %d" % len(hit))
    return hit[0]

def between(lines, begin, end):
    try:
        i = lines.index(begin)
        j = lines.index(end, i + 1)
    except ValueError:
        sys.exit("smoke_reopen: missing " + begin)
    return "\n".join(lines[i + 1:j])

before = one(save, "CHECK who-before=")
after = one(open_, "CHECK who-after=")
if "REOPEN_SAVE_OK" not in save or "REOPEN_UNIT_OK" not in open_:
    sys.exit("smoke_reopen: phase marker missing")
if "helper" not in before or "closer" not in before:
    sys.exit("smoke_reopen: save who lost the engine record: " + before)

code0 = between(open_, "REOPEN code-before-begin", "REOPEN code-before-end")
code1 = between(open_, "REOPEN code-after-begin", "REOPEN code-after-end")
gap = "GAPS persist-global" in open_
title = any(ln.startswith("TITLE deserialize-workspace") for ln in open_)
root_same = "REOPEN root=same" in open_
canary_ok = ("REOPEN canary-before=a,b" in open_
             and "REOPEN canary-after=a,b" in open_)
sane_ok = "REOPEN sane-before=yes" in open_ and "REOPEN sane-after=yes" in open_
deser_ok = "REOPEN deser=yes" in open_

if root_same and canary_ok and sane_ok and deser_ok and code0 == code1 and before == after:
    if gap:
        sys.exit("smoke_reopen: healthy reopen still logged a gap")
    sys.exit(0)

authors = ("helper", "kid", "macro", "law", "nobody")
if gap and title and "soft-only" in after and any(w in after for w in authors):
    if "sum=" in after:
        sys.exit("smoke_reopen: soft-only invented a sum")
    sys.exit(0)

sys.exit("smoke_reopen: neither engine who nor soft-only\nbefore=%s\nafter=%s\nroot=%s canary=%s sane=%s deser=%s gap=%s"
         % (before, after, root_same, canary_ok, sane_ok, deser_ok, gap))
PY

echo PAD_REOPEN_OK
