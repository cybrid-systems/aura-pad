#!/usr/bin/env bash
# Soft M0 smoke. Image ghcr.io/cybrid-systems/dev:v1.0.9, tip binary only.
# Never build_soft4132. Host GLIBC may be too old — always run Soft in docker.
# Native-in-container: --entrypoint gosu, no nested docker.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
mkdir -p "$ROOT/out"
if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "smoke_soft: docker not available" >&2
  exit 1
fi
"${DOCKER[@]}" run --rm --entrypoint /usr/local/bin/gosu \
  -v "$AURA_SRC":/workspace/aura-grok \
  -v "$ROOT":/workspace/aura-pad \
  -w /workspace/aura-pad \
  -e AURA_PATH=/workspace/aura-grok/lib \
  -e AURA_PIPELINE_STRICT=0 \
  -e AURA_SANDBOX=off \
  -e AURA_BIN=/workspace/aura-grok/build/aura \
  "$IMG" \
  dev /workspace/aura-grok/build/aura /workspace/aura-pad/soft/pad/m0_smoke.aura \
  >"$ROOT/out/m0_smoke.txt" 2>"$ROOT/out/m0_smoke.err"
cat "$ROOT/out/m0_smoke.txt"
if [[ -s "$ROOT/out/m0_smoke.err" ]]; then
  cat "$ROOT/out/m0_smoke.err" >&2
fi
fail=0
grep -q 'RACE gentle=' "$ROOT/out/m0_smoke.txt" || fail=1
grep -q 'KEEP mid=' "$ROOT/out/m0_smoke.txt" || fail=1
grep -q 'DROP mid=' "$ROOT/out/m0_smoke.txt" || fail=1
grep -q 'REJECT mid=[0-9]* reason=' "$ROOT/out/m0_smoke.txt" || fail=1
grep -q 'PAD_M0_OK' "$ROOT/out/m0_smoke.txt" || fail=1
grep -q 'WORLD line=' "$ROOT/out/m0_smoke.txt" || fail=1
if grep -q 'WORLD line=fiber_live' "$ROOT/out/m0_smoke.txt"; then
  grep -q 'WORLD line=fiber_live backend=[1-9][0-9]* joins=2/2' "$ROOT/out/m0_smoke.txt" || fail=1
elif grep -q 'WORLD line=host-sequential' "$ROOT/out/m0_smoke.txt"; then
  :
else
  fail=1
fi
if grep -q 'PAD_M0_FAIL' "$ROOT/out/m0_smoke.txt"; then
  fail=1
fi
if grep -q 'WORLD_FAIL\|KEEP_FAIL\|TIE_FAIL\|REJECT_FAIL\|WANT=' "$ROOT/out/m0_smoke.txt"; then
  fail=1
fi
if grep -qiE 'error:|unbound variable' "$ROOT/out/m0_smoke.txt" "$ROOT/out/m0_smoke.err"; then
  fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_soft: PAD_M0_OK checks failed" >&2
  exit 1
fi
echo "smoke_soft: PAD_M0_OK"
