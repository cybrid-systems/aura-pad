#!/usr/bin/env bash
# Soft play child for scripts/bench_editors.sh: same as soft_play.sh but
# runs aura directly (we are already inside the dev container).
exec /usr/bin/stdbuf -oL -eL /workspace/aura-grok/build/aura /workspace/aura-pad/soft/pad/play.aura
