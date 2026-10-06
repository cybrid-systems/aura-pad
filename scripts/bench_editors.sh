#!/usr/bin/env bash
# Same-harness latency: aura-pad vs vim vs emacs, keystroke -> terminal
# output, one pseudo-terminal each (scripts/latency_pty.py), all inside
# ghcr.io/cybrid-systems/dev:v1.0.9 on the same box, same 12-row file
# (*lc-big-page*), same key bytes, cursor at the end of row 6.
#   vim  : vim -u NONE -N, syntax on, ft=scheme (insert mode)
#   emacs: emacs -nw -Q (scheme-mode, font-lock/jit-lock, show-paren)
#   pad  : out/bench/pad_play --ansi -> Soft play.aura (PAD_PAGE=big)
#   pad-defer: same with PAD_DEFER=1 (docs/perf-aura.md early frame)
# Output: out/bench/editors.txt (LATENCY lines). Not a smoke: timing on a
# shared box; see docs/perf-emacs.md for what is and is not comparable.
# Needs network once to apt-get emacs-nox inside the throwaway container.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
N="${BENCH_N:-60}"
RUNS="${BENCH_RUNS:-2}"
mkdir -p "$ROOT/out/bench"
if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
# the page file, byte-identical to *lc-big-page*
python3 - "$ROOT" <<'PY'
import re, sys
root = sys.argv[1]
s = open(f"{root}/soft/pad/lc.aura").read()
body = s[s.index("(define *lc-big-page*"):]
body = body[:body.index("))") + 2]
parts = re.findall(r'"((?:[^"\\]|\\.)*)"', body)
txt = "".join(p.encode().decode("unicode_escape") for p in parts)
open(f"{root}/out/bench/page.scm", "w").write(txt + "\n")
PY
"${DOCKER[@]}" run --rm -i --entrypoint bash \
  -v "${AURA_SRC}:/workspace/aura-grok" -v "${ROOT}:/workspace/aura-pad" \
  -w /workspace/aura-pad \
  -e AURA_PATH=/workspace/aura-grok/lib -e AURA_PIPELINE_STRICT=0 -e AURA_SANDBOX=off \
  -e AURA_BIN=/workspace/aura-grok/build/aura -e PAD_PAGE=big \
  -e N="$N" -e RUNS="$RUNS" -e COLD_N="${BENCH_COLD_N:-12}" "$IMG" -s <<'IN'
set -euo pipefail
cd /workspace/aura-pad
if ! command -v emacs >/dev/null 2>&1; then
  (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends emacs-nox) >/tmp/apt.log 2>&1 || true
fi
cc -std=c11 -O2 -Wall -Wextra c/snap.c c/pad_play.c -o out/bench/pad_play
P=out/bench/page.scm
L="python3 scripts/latency_pty.py --n $N --cold 22:7f --cold-n ${COLD_N:-12}"
DOWN6=1b5b42,1b5b42,1b5b42,1b5b42,1b5b42,1b5b42
{
  echo "BENCH host=$(hostname) nproc=$(nproc) date=$(date -Is)"
  echo "VERSIONS vim=\"$(vim --version | head -1)\" emacs=\"$(emacs --version 2>/dev/null | head -1 || echo missing)\" aura=$(cd /workspace/aura-grok && git rev-parse --short HEAD 2>/dev/null || echo ?)"
  for r in $(seq 1 "$RUNS"); do
    $L --name pad --setup-keys "$DOWN6,05" --startup-quiet 2500 -- \
      out/bench/pad_play --ansi scripts/bench_soft_play.sh
    # PAD_DEFER=1: early frame for string edits, exact frame right after
    PAD_DEFER=1 $L --name pad-defer --setup-keys "$DOWN6,05" --startup-quiet 2500 -- \
      out/bench/pad_play --ansi scripts/bench_soft_play.sh
    $L --name vim --setup-keys 3747,24,61 -- \
      vim -u NONE -i NONE -N -n --cmd 'set bs=2 ttimeoutlen=10' --cmd 'syntax on' -c 'set ft=scheme' "$P"
    if command -v emacs >/dev/null 2>&1; then
      $L --name emacs --setup-keys "1b3c,0e,0e,0e,0e,0e,0e,05" -- emacs -nw -Q "$P"
    else
      echo "LATENCY name=emacs missing=1"
    fi
  done
} 2>&1 | grep -E '^(BENCH|VERSIONS|LATENCY)'
IN
