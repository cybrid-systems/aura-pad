#!/usr/bin/env bash
# Shared Soft runner: tip aura inside ghcr.io/cybrid-systems/dev:v1.0.9.
# Soft runs natively in the container (no nested docker). Never build_soft4132.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
SRC="${1:?aura source path}"
shift || true

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "run_soft: docker not available" >&2
  exit 1
fi

exec "${DOCKER[@]}" run --rm -i --entrypoint /usr/local/bin/gosu \
  -v "${AURA_SRC}:/workspace/aura-grok" \
  -v "${ROOT}:/workspace/aura-pad" \
  -w /workspace/aura-pad \
  -e AURA_PATH=/workspace/aura-grok/lib \
  -e AURA_PIPELINE_STRICT=0 \
  -e AURA_SANDBOX=off \
  -e AURA_BIN=/workspace/aura-grok/build/aura \
  -e "PAD_HORIZON=${PAD_HORIZON:-}" \
  -e "PAD_DEFER=${PAD_DEFER:-}" \
  -e "PAD_PAGE=${PAD_PAGE:-}" \
  -e "PAD_TEST_PENDING=${PAD_TEST_PENDING:-}" \
  -e "PAD_BURN_ROUNDS=${PAD_BURN_ROUNDS:-}" \
  -e "PAD_ROUND_DIR=${PAD_ROUND_DIR:-}" \
  -e "PAD_PROPOSE_FILE=${PAD_PROPOSE_FILE:-}" \
  -e "AURA_MUTATE_TYPE_GATE=${AURA_MUTATE_TYPE_GATE:-}" \
  "${IMG}" \
  dev /usr/bin/stdbuf -oL -eL /workspace/aura-grok/build/aura "$SRC" "$@"
