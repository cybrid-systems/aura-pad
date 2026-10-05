#!/usr/bin/env bash
# Soft play child for c/pad_play (and headless smoke).
# stdin : "IN <byte>" / "KEY <word>" / "QUIT" lines.
# stdout: SNAP v1 pad blocks only (line-buffered). Soft owns the keymap.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/play.aura
