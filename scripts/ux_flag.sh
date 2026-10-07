#!/usr/bin/env bash
# Step 1. PAD_SENTENCE=1 skips pad:vi-boot!. The flag off still boots vi.
# Prints PAD_UX_FLAG_OK. Does not change c/aura_pad.c.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA="${AURA_BIN:-}"
if [[ -z "$AURA" || ! -x "$AURA" ]]; then
  for c in /workspace/aura-grok/build/aura \
           "$HOME/code/grok-dev/aura-grok/build/aura" \
           /home/dev/code/grok-dev/aura-grok/build/aura; do
    if [[ -x "$c" ]]; then AURA="$c"; break; fi
  done
fi
if [[ -z "${AURA:-}" || ! -x "$AURA" ]]; then
  echo "ux_flag: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/ux-flag"
rm -rf "$OUT"
mkdir -p "$OUT"

run_play() { # stdin is the key stream. Extra env is already exported.
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/play.aura"
}

printf 'QUIT\n' | PAD_VI=1 run_play >"$OUT/vi.txt" 2>"$OUT/vi.err" \
  || { cat "$OUT/vi.err" >&2; exit 1; }
printf 'QUIT\n' | PAD_VI=1 PAD_SENTENCE=1 run_play >"$OUT/ux.txt" 2>"$OUT/ux.err" \
  || { cat "$OUT/ux.err" >&2; exit 1; }

grep -q '\[normal\]' "$OUT/vi.txt" || { echo "ux_flag: vi frame has no [normal]" >&2; exit 1; }
if grep -q '\[normal\]' "$OUT/ux.txt"; then
  echo "ux_flag: sentence frame called vi-boot" >&2
  exit 1
fi
if grep -qiE 'error:|unbound variable' "$OUT/vi.txt" "$OUT/vi.err" "$OUT/ux.txt" "$OUT/ux.err"; then
  echo "ux_flag: Soft error" >&2
  exit 1
fi
# The two frames differ only by the vi chrome vi-boot adds.
grep -q '^TITLE ' "$OUT/ux.txt" || { echo "ux_flag: no frame" >&2; exit 1; }
echo PAD_UX_FLAG_OK
