#!/usr/bin/env bash
# Build the thin C viewport into out/c/ (pad_view, pad_play).
# Host cc by default; PAD_C_DOCKER=1 (or no host cc) builds inside
# ghcr.io/cybrid-systems/dev:v1.0.9. PAD_C_ASAN=1 adds ASan/UBSan.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
mkdir -p "$ROOT/out/c"
FLAGS=(-std=c11 -O2 -Wall -Wextra -pedantic -Werror)
if [[ "${PAD_C_ASAN:-0}" == "1" ]]; then
  FLAGS+=(-g -fsanitize=address,undefined -fno-omit-frame-pointer)
fi
build() { # $1 = compiler prefix words..., run in $2 root
  local root="$1"; shift
  "$@" cc "${FLAGS[@]}" "$root/c/snap.c" "$root/c/pad_view.c" -o "$root/out/c/pad_view"
  "$@" cc "${FLAGS[@]}" "$root/c/snap.c" "$root/c/pad_play.c" -o "$root/out/c/pad_play"
}
if [[ "${PAD_C_DOCKER:-0}" != "1" ]] && command -v cc >/dev/null 2>&1; then
  build "$ROOT" env
  echo "build_c: host cc -> out/c/pad_view out/c/pad_play"
else
  if docker info >/dev/null 2>&1; then DOCKER=(docker)
  elif sudo docker info >/dev/null 2>&1; then DOCKER=(sudo docker)
  else echo "build_c: no cc and no docker" >&2; exit 1; fi
  build /workspace/aura-pad "${DOCKER[@]}" run --rm --entrypoint /usr/local/bin/gosu \
    -v "$ROOT:/workspace/aura-pad" -w /workspace/aura-pad "$IMG" dev
  echo "build_c: docker cc -> out/c/pad_view out/c/pad_play"
fi
