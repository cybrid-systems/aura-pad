#!/usr/bin/env bash
# M0 entry: Soft dual-keymap race → PAD_M0_OK
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/smoke_soft.sh"
