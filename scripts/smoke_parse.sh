#!/usr/bin/env bash
# Step 38. A model reply is ops plus checks, or one sentence.
# A bad shape is a gate refusal and does not run the form.
# Does not call docker. Prints PAD_TX_PARSE_OK.
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
  echo "smoke_parse: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/parse"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/tx.aura" \
  "$ROOT/soft/pad/parse_test.aura"

fail() { echo "smoke_parse: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
tx = (root / "soft/pad/tx.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/parse_test.aura").read_text(encoding="utf-8")
ok = (root / "soft/pad/fixtures/propose_ok.txt").read_text(encoding="utf-8")
bad = (root / "soft/pad/fixtures/propose_bad_type.txt").read_text(encoding="utf-8")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test:
        sys.exit("smoke_parse: test contains " + banned)
a = tx.find("(define *tx-max-ops*")
b = tx.find("(define (pad:tx-read ")
if a < 0 or b < a:
    sys.exit("smoke_parse: parse block is missing")
body = tx[a:b]
for banned in ("string-split", "string-trim", "string-replace",
               "mutate:rebind", "ast:snapshot", "typed-mutate", "eval"):
    if banned in body:
        sys.exit("smoke_parse: parse uses " + banned)
if "(define (pad:tx-parse " not in body:
    sys.exit("smoke_parse: missing pad:tx-parse")
if "*tx-max-ops* 4" not in body:
    sys.exit("smoke_parse: op cap is not 4")
if '"ops"' not in body or '"prose"' not in body or '"gate"' not in body:
    sys.exit("smoke_parse: kinds are missing")
if "=(lambda " not in ok or not ok.startswith("hello=") or "check hello 3 5" not in ok:
    sys.exit("smoke_parse: ok fixture is not one op plus a check")
if "=(lambda " not in bad or "check hello 3 0" not in bad:
    sys.exit("smoke_parse: bad fixture is not one op plus a check")
PY

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/parse_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "soft error"
fi

for line in \
  "CHECK ok kind=ops" \
  "CHECK ok rebind=0" \
  "CHECK ok snap=0" \
  "CHECK ok code=same" \
  "CHECK ok n=1" \
  "CHECK ok name=hello" \
  "CHECK ok lam=(lambda (x) (+ x 2))" \
  "CHECK ok checks=1" \
  "CHECK ok check=hello 3 5" \
  "CHECK bad kind=ops" \
  "CHECK bad rebind=0" \
  "CHECK bad snap=0" \
  "CHECK bad code=same" \
  "CHECK bad n=1" \
  "CHECK bad name=hello" \
  "CHECK bad lam=(lambda (x) (+ x \"a\"))" \
  "CHECK bad checks=1" \
  "CHECK bad check=hello 3 0" \
  "CHECK prose kind=prose" \
  "CHECK prose rebind=0" \
  "CHECK prose snap=0" \
  "CHECK prose code=same" \
  "CHECK prose text=same" \
  "CHECK four kind=ops" \
  "CHECK four rebind=0" \
  "CHECK four snap=0" \
  "CHECK four n=4" \
  "CHECK four first=a" \
  "CHECK four last=d" \
  "CHECK five kind=gate" \
  "CHECK five rebind=0" \
  "CHECK five snap=0" \
  "CHECK five why=too-many" \
  "CHECK twice kind=gate" \
  "CHECK twice rebind=0" \
  "CHECK twice snap=0" \
  "CHECK twice why=twice" \
  "CHECK lam kind=gate" \
  "CHECK lam rebind=0" \
  "CHECK lam snap=0" \
  "CHECK lam why=not-lambda" \
  "CHECK empty kind=prose" \
  "CHECK empty rebind=0" \
  "CHECK empty snap=0" \
  "PARSE_UNIT_OK"
do
  grep -qx "$line" "$OUT/unit.txt" || fail "missing $line"
done

echo PAD_TX_PARSE_OK
