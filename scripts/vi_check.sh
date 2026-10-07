#!/usr/bin/env bash
# Vi normal/insert + emacs ctrl-b/f/p/n, and a file round-trip through
# play.aura. Prints PAD_VI_TEST_OK. Uses a native aura when one is on
# this machine, otherwise scripts/run_soft.sh (docker).
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

# Host path of the repo, and the path Soft sees (docker mounts the repo
# at /workspace/aura-pad).
if [[ -n "${AURA:-}" && -x "$AURA" ]]; then
  BOX="$ROOT"
else
  BOX="/workspace/aura-pad"
fi
OUT="$ROOT/out/vi-check"
rm -rf "$OUT"
mkdir -p "$OUT"

run_aura() { # $1 aura file (host path). stdin is the program's stdin.
  if [[ -n "${AURA:-}" && -x "$AURA" ]]; then
    local lib
    lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
    if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
      lib=/workspace/aura-grok/lib
    fi
    AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
      AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
      "$AURA" "$1"
  else
    PAD_POLL=0 PAD_DEFER=0 \
      bash "$ROOT/scripts/run_soft.sh" "/workspace/aura-pad/${1#"$ROOT"/}"
  fi
}

run_aura "$ROOT/soft/pad/vi_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }
cat "$OUT/unit.txt"
if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  echo "vi_check: Soft error" >&2
  cat "$OUT/unit.err" >&2
  exit 1
fi
grep -q '^PAD_VI_TEST_OK$' "$OUT/unit.txt" || { echo "vi_check: unit" >&2; exit 1; }

# File editor: ctrl-f, ctrl-n, i, Z, Esc, save. Page becomes ab / cZd.
printf 'ab\ncd\n' >"$OUT/page.txt"
printf '%s\n' 'IN 6' 'IN 14' 'IN 105' 'IN 90' 'IN 27' 'IN 24' 'IN 19' 'IN 17' \
  | PAD_VI=1 PAD_FILE="$BOX/out/vi-check/page.txt" \
    run_aura "$ROOT/soft/pad/play.aura" >"$OUT/play.txt" 2>"$OUT/play.err" \
  || { cat "$OUT/play.err" >&2; exit 1; }
if grep -qiE 'error:|unbound variable' "$OUT/play.txt" "$OUT/play.err"; then
  echo "vi_check: play Soft error" >&2
  cat "$OUT/play.err" >&2
  exit 1
fi
# $(cat) drops trailing newlines, so keep a sentinel.
got="$(cat "$OUT/page.txt"; printf x)"
[[ "$got" == $'ab\ncZd\nx' ]] || { echo "vi_check: file is $(printf %q "$got")" >&2; exit 1; }
grep -q '\[normal\]' "$OUT/play.txt" && grep -q '\[insert\]' "$OUT/play.txt" \
  || { echo "vi_check: mode badge missing" >&2; exit 1; }

# A letter in normal mode must not land in the file.
printf 'ab\n' >"$OUT/plain.txt"
printf '%s\n' 'IN 90' 'IN 24' 'IN 19' 'IN 17' \
  | PAD_VI=1 PAD_FILE="$BOX/out/vi-check/plain.txt" \
    run_aura "$ROOT/soft/pad/play.aura" >"$OUT/plain.out" 2>"$OUT/plain.err" \
  || { cat "$OUT/plain.err" >&2; exit 1; }
[[ "$(cat "$OUT/plain.txt"; printf x)" == $'ab\nx' ]] || { echo "vi_check: normal Z inserted" >&2; exit 1; }

# Save failure is an ERR line Soft prints outside the snapshot.
mkdir -p "$OUT/gone"
rmdir "$OUT/gone"
printf '%s\n' 'IN 105' 'IN 65' 'IN 24' 'IN 19' 'QUIT' \
  | PAD_VI=1 PAD_FILE="$BOX/out/vi-check/gone/x.txt" \
    run_aura "$ROOT/soft/pad/play.aura" >"$OUT/fail.out" 2>"$OUT/fail.err" \
  || { cat "$OUT/fail.err" >&2; exit 1; }
grep -q '^ERR could not save x.txt$' "$OUT/fail.out" \
  || { echo "vi_check: no ERR line" >&2; cat "$OUT/fail.out" >&2; exit 1; }

echo PAD_VI_TEST_OK
