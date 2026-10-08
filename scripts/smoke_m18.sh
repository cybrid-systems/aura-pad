#!/usr/bin/env bash
# Step 20. Cursor times before and after a sentence check.
# The Emacs frame gate is the one in scripts/smoke_perf.sh: one retry
# for wall-clock noise, and the same failure sentence when a cursor is
# not under 16000 microseconds. This script runs the native binary.
# It does not call docker. Prints the PERF_READ lines.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA="${AURA_BIN:-}"
if [[ -z "$AURA" || ! -x "$AURA" ]]; then
  # A Release binary meets the 16 ms frame. build/aura in this
  # workspace is often a Debug tree of the same commit, and that tree
  # is slower than one frame. Prefer build-release when it exists.
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
  echo "smoke_m18: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/m18"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/perf_read_test.aura" \
  "$ROOT/soft/pad/ux.aura" \
  "$ROOT/soft/pad/emacs_test.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
ux = (root / "soft/pad/ux.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/perf_read_test.aura").read_text(encoding="utf-8")

def body(src, name):
    key = "(define (" + name
    i = src.find(key)
    if i < 0:
        sys.exit("smoke_m18: missing " + name)
    j = src.find("\n(define ", i + 1)
    if j < 0:
        j = len(src)
    return src[i:j]

for banned in ("string-split", "string-trim", "string-replace"):
    if banned in test:
        sys.exit("smoke_m18: banned word " + banned)
for name in ("pad:ux-move! ", "pad:ux-say-at)", "pad:ux-arrow! "):
    part = body(ux, name)
    if "define-lookup" in part:
        sys.exit("smoke_m18: " + name + " calls define-lookup")
PY

fail() { echo "smoke_m18: $*" >&2; exit 1; }

soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

run_emacs() {
  unset PAD_SENTENCE
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/emacs_test.aura" >"$OUT/emacs.txt" 2>"$OUT/emacs.err"
  grep -E '^(ET_|PERF_EMACS|EMACS_TEST|PAD_PERF_EMACS)' "$OUT/emacs.txt" || true
  if soft_errs "$OUT/emacs.txt" "$OUT/emacs.err"; then
    cat "$OUT/emacs.err" >&2 || true
    echo "smoke_m18: Soft error in emacs_test" >&2
    exit 1
  fi
  if ! grep -qE '^EMACS_TEST checks=[0-9]+ fail=0$' "$OUT/emacs.txt"; then
    echo "PAD_PERF_EMACS_FAIL (fast path != reference)" >&2
    exit 1
  fi
  grep -q '^PAD_PERF_EMACS_OK$' "$OUT/emacs.txt"
}

run_read() {
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    PAD_SENTENCE=1 \
    "$AURA" "$ROOT/soft/pad/perf_read_test.aura" >"$OUT/read.txt" 2>"$OUT/read.err"
  if soft_errs "$OUT/read.txt" "$OUT/read.err"; then
    cat "$OUT/read.txt" "$OUT/read.err" >&2 || true
    echo "smoke_m18: Soft error in the sentence cursor" >&2
    exit 1
  fi
  grep -qx 'PERF_READ_UNIT_OK' "$OUT/read.txt" || {
    cat "$OUT/read.txt" "$OUT/read.err" >&2
    fail "sentence cursor did not finish"
  }
  grep -qx 'PERF_READ flag=on' "$OUT/read.txt" || fail "sentence flag was off"
  grep -qx 'PERF_READ cold_lookup=0' "$OUT/read.txt" || fail "cold arrow called define-lookup"
  grep -qx 'PERF_READ check=checked' "$OUT/read.txt" || fail "page did not check"
  grep -qx 'PERF_READ post_lookup=0' "$OUT/read.txt" || fail "arrow called define-lookup after the check"
  grep -qE '^PERF_READ cold_cursor_ms=[0-9]+$' "$OUT/read.txt" || fail "cold cursor was not published"
  grep -qE '^PERF_READ post_check_cursor_ms=[0-9]+$' "$OUT/read.txt" || fail "post-check cursor was not published"
  grep -E '^PERF_READ (cold_cursor_ms|post_check_cursor_ms|cold_lookup|post_lookup|check)=' "$OUT/read.txt"
  local us
  us="$(sed -n 's/^PERF_READ post_check_cursor_us=//p' "$OUT/read.txt" | tail -n 1)"
  [[ "$us" =~ ^[0-9]+$ ]] || fail "post-check microseconds missing"
  if (( us >= 16000 )); then
    return 1
  fi
  return 0
}

echo "smoke_m18: sentence cursor, before and after check"
rover=0
rattempt=1
if ! run_read; then
  rattempt=2
  echo "smoke_m18: cursor retry (wall-clock noise on a shared box)"
  run_read || rover=1
fi

echo "smoke_m18: Emacs frame, sentence flag unset"
eover=0
eattempt=1
if ! run_emacs; then
  eattempt=2
  echo "smoke_m18: emacs retry (wall-clock noise on a shared box)"
  run_emacs || eover=1
fi

if (( rover || eover )); then
  echo "PAD_PERF_EMACS_FAIL (over the 16 ms frame)" >&2
  exit 1
fi
echo "smoke_m18: PAD_PERF_EMACS_OK attempt=$eattempt"
echo "smoke_m18: PERF_READ attempt=$rattempt"
echo PAD_M18_PERF_OK
