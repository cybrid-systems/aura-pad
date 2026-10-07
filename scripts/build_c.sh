#!/usr/bin/env bash
# Build the thin C viewport into out/c/: pad_view, pad_play (dev/smoke
# viewport driven by scripts/soft_play.sh) and aura-pad (the one-command
# editor: starts Soft itself, no scripts).
# Host cc by default; PAD_C_DOCKER=1 (or no host cc) builds inside
# ghcr.io/cybrid-systems/dev:v1.0.9. PAD_C_ASAN=1 adds ASan/UBSan.
#
#   scripts/build_c.sh --install [PREFIX]
# also installs aura-pad: PREFIX/bin/aura-pad plus the pad's Soft files in
# PREFIX/share/aura-pad/soft/pad (that path is baked into the binary).
# PREFIX: the argument, else $PREFIX, else ~/.local.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
INSTALL=0
DEST=""
if [[ "${1:-}" == "--install" ]]; then
  INSTALL=1
  DEST="${2:-${PREFIX:-$HOME/.local}}"
  mkdir -p "$DEST"
  DEST="$(cd "$DEST" && pwd)"
fi
mkdir -p "$ROOT/out/c"
FLAGS=(-std=c11 -O2 -Wall -Wextra -pedantic -Werror)
if [[ "${PAD_C_ASAN:-0}" == "1" ]]; then
  FLAGS+=(-g -fsanitize=address,undefined -fno-omit-frame-pointer)
fi
SHARE_DEF=()
if [[ "$INSTALL" == "1" ]]; then
  SHARE_DEF=("-DAURA_PAD_SHARE=\"$DEST/share/aura-pad\"")
fi
build() { # $1 = root, then compiler prefix words...
  local root="$1"; shift
  "$@" cc "${FLAGS[@]}" "$root/c/snap.c" "$root/c/pad_view.c" -o "$root/out/c/pad_view"
  "$@" cc "${FLAGS[@]}" "$root/c/snap.c" "$root/c/play_loop.c" "$root/c/pad_play.c" -o "$root/out/c/pad_play"
  "$@" cc "${FLAGS[@]}" "${SHARE_DEF[@]}" "$root/c/snap.c" "$root/c/play_loop.c" "$root/c/aura_pad.c" \
    -o "$root/out/c/aura-pad"
}
if [[ "${PAD_C_DOCKER:-0}" != "1" ]] && command -v cc >/dev/null 2>&1; then
  build "$ROOT" env
  echo "build_c: host cc -> out/c/pad_view out/c/pad_play out/c/aura-pad"
else
  if docker info >/dev/null 2>&1; then DOCKER=(docker)
  elif sudo docker info >/dev/null 2>&1; then DOCKER=(sudo docker)
  else echo "build_c: no cc and no docker" >&2; exit 1; fi
  build /workspace/aura-pad "${DOCKER[@]}" run --rm --entrypoint /usr/local/bin/gosu \
    -v "$ROOT:/workspace/aura-pad" -w /workspace/aura-pad "$IMG" dev
  echo "build_c: docker cc -> out/c/pad_view out/c/pad_play out/c/aura-pad"
fi
if [[ "$INSTALL" == "1" ]]; then
  share="$DEST/share/aura-pad"
  mkdir -p "$DEST/bin" "$share"
  rm -rf "$share/soft"
  mkdir -p "$share/soft/pad"
  cp "$ROOT"/soft/pad/*.aura "$share/soft/pad/"
  install -m 0755 "$ROOT/out/c/aura-pad" "$DEST/bin/aura-pad"
  echo "build_c: installed $DEST/bin/aura-pad (Soft files in $share/soft/pad)"
  case ":$PATH:" in
    *":$DEST/bin:"*) ;;
    *) echo "build_c: add $DEST/bin to PATH to run aura-pad by name" ;;
  esac
fi
