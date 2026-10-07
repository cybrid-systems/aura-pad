#!/usr/bin/env bash
# aura-pad, the one-command editor (`aura-pad [FILE]`, c/aura_pad.c +
# soft/pad/file.aura). C launches Soft directly (no script) and blits;
# Soft opens and saves FILE.
#   1. paren balance of file.aura / play.aura                     PAREN_OK
#   2. build + install (scripts/build_c.sh --install, and cmake
#      --install when cmake is there) into out/cli/smoke     CLI_INSTALL_OK
#   3. --where: installed share dir, source tree, AURA_PAD_HOME;
#      bad AURA_PAD_HOME is a clear message + exit 127        CLI_WHERE_OK
#   4. no aura and no docker: clear message, exit 127        CLI_MISSING_OK
#      (skipped when an aura on this machine runs natively)
#   5. Soft file mode, headless (scripts/cli_soft_check.py)    CLI_SOFT_OK
#   6. pty end to end with the installed binary on this host, in
#      whatever mode it picks (native, or docker fallback): open+save,
#      new file, unsaved-quit guard, ctrl-\ emergency exit; terminal
#      restored (scripts/cli_pty.py)                CLI_PTY_OK mode=..
#   7. when docker is here: the same four in the dev container, built
#      and installed there, native aura, no docker inside
#                                            CLI_PTY_OK mode=native-box
# Ends with PAD_CLI_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/cli/smoke"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
rm -rf "$OUT"; mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" "$ROOT/soft/pad/file.aura" "$ROOT/soft/pad/play.aura" \
  "$ROOT/soft/pad/vi.aura" "$ROOT/soft/pad/vi_test.aura" \
  "$ROOT/soft/pad/screen.aura" "$ROOT/soft/pad/emacs.aura" \
  "$ROOT/soft/pad/win.aura" "$ROOT/soft/pad/win_test.aura" \
  "$ROOT/soft/pad/layout.aura" "$ROOT/soft/pad/layout_test.aura"
bash "$ROOT/scripts/vi_check.sh"

# 2. install
INST="$OUT/inst"
bash "$ROOT/scripts/build_c.sh" --install "$INST" | tee "$OUT/install.txt"
AP="$INST/bin/aura-pad"
test -x "$AP" && test -f "$INST/share/aura-pad/soft/pad/play.aura" && test -f "$INST/share/aura-pad/soft/pad/file.aura" \
  || { echo "smoke_cli: install layout" >&2; exit 1; }
"$AP" --version | grep -q '^aura-pad ' || { echo "smoke_cli: --version" >&2; exit 1; }
if command -v cmake >/dev/null 2>&1; then
  cmake -S "$ROOT/c" -B "$OUT/cmake" -DCMAKE_INSTALL_PREFIX="$OUT/cmake_inst" >"$OUT/cmake.txt" 2>&1
  cmake --build "$OUT/cmake" >>"$OUT/cmake.txt" 2>&1
  cmake --install "$OUT/cmake" >>"$OUT/cmake.txt" 2>&1
  test -x "$OUT/cmake_inst/bin/aura-pad" && test -f "$OUT/cmake_inst/share/aura-pad/soft/pad/play.aura" \
    || { cat "$OUT/cmake.txt" >&2; echo "smoke_cli: cmake --install layout" >&2; exit 1; }
  grep -q "^home=$OUT/cmake_inst/share/aura-pad\$" <("$OUT/cmake_inst/bin/aura-pad" --where) \
    || { echo "smoke_cli: cmake build does not find its share dir" >&2; exit 1; }
  echo "smoke_cli: cmake --install OK"
fi
echo "smoke_cli: CLI_INSTALL_OK"

# 3. where
"$AP" --where "$OUT/w.txt" >"$OUT/where.txt"
cat "$OUT/where.txt"
grep -q "^home=$INST/share/aura-pad\$" "$OUT/where.txt" \
  && grep -q "^file=$OUT/w.txt\$" "$OUT/where.txt" \
  && grep -qE '^mode=(native|docker)$' "$OUT/where.txt" \
  || { echo "smoke_cli: installed --where" >&2; exit 1; }
# out/c/aura-pad from a plain build (no baked share dir) finds the tree
bash "$ROOT/scripts/build_c.sh" >/dev/null
grep -q "^home=$ROOT\$" <("$ROOT/out/c/aura-pad" --where) || { echo "smoke_cli: source-tree home" >&2; exit 1; }
grep -q "^home=$ROOT\$" <(AURA_PAD_HOME="$ROOT" "$AP" --where) || { echo "smoke_cli: AURA_PAD_HOME" >&2; exit 1; }
set +e
AURA_PAD_HOME="$OUT/nothing" "$AP" --where >/dev/null 2>"$OUT/badhome.err"; rc=$?
set -e
[[ $rc == 127 ]] && grep -q 'no soft/pad/play.aura' "$OUT/badhome.err" || { cat "$OUT/badhome.err" >&2; exit 1; }
# relative FILE, file in a missing folder: still an absolute path for Soft
(cd "$OUT" && "$AP" --where rel.txt) | grep -q "^file=$OUT/rel.txt\$" || { echo "smoke_cli: relative FILE" >&2; exit 1; }
echo "smoke_cli: CLI_WHERE_OK"

# 4. nothing to run Soft with
MODE="$(sed -n 's/^mode=//p' "$OUT/where.txt")"
NATIVE_HERE="$(AURA_PAD_NO_DOCKER=1 AURA_BIN=/nonexistent PATH=/usr/bin:/bin "$AP" --where 2>/dev/null | sed -n 's/^mode=//p' || true)"
if [[ "$NATIVE_HERE" == "native" ]]; then
  echo "CLI_MISSING_SKIP reason=a known aura path runs natively here"
else
  set +e
  AURA_PAD_NO_DOCKER=1 AURA_BIN=/nonexistent PATH=/usr/bin:/bin "$AP" "$OUT/m.txt" </dev/null >"$OUT/missing.out" 2>"$OUT/missing.err"; rc=$?
  set -e
  cat "$OUT/missing.err"
  [[ $rc == 127 ]] && grep -q 'cannot find Aura' "$OUT/missing.err" && [[ ! -e "$OUT/m.txt" ]] \
    || { echo "smoke_cli: missing-aura message (rc=$rc)" >&2; exit 1; }
  echo "smoke_cli: CLI_MISSING_OK"
fi

# 5. Soft file mode
python3 "$ROOT/scripts/cli_soft_check.py" "$OUT/soft" | tee "$OUT/soft.txt"
grep -q '^CLI_SOFT_OK ' "$OUT/soft.txt" || exit 1

# 6. pty, this host
mkdir -p "$OUT/pty"
for sc in open new unsaved emergency vi; do
  timeout 180 python3 "$ROOT/scripts/cli_pty.py" "$sc" "$OUT/pty/$sc.txt" -- "$AP" "$OUT/pty/$sc.txt" | tee "$OUT/pty_$sc.txt"
  grep -q '^CLI_PTY_OK ' "$OUT/pty_$sc.txt" || { echo "smoke_cli: pty $sc ($MODE)" >&2; exit 1; }
done
echo "smoke_cli: CLI_PTY_OK mode=$MODE"

# 7. native in the dev container (a machine with aura and without docker)
if docker info >/dev/null 2>&1; then DOCKER=(docker)
elif sudo -n docker info >/dev/null 2>&1; then DOCKER=(sudo -n docker)
else DOCKER=(); fi
if [[ ${#DOCKER[@]} -gt 0 && -x "${AURA_SRC:-/workspace/aura-grok}/build/aura" ]]; then
  "${DOCKER[@]}" run --rm -i --entrypoint /usr/local/bin/gosu \
    -v "${AURA_SRC:-/workspace/aura-grok}:/workspace/aura-grok" -v "$ROOT:/workspace/aura-pad:ro" \
    "$IMG" dev bash -s >"$OUT/native.txt" 2>&1 <<'IN' || true
set -e
mkdir -p /tmp/ap && cp -r /workspace/aura-pad/c /workspace/aura-pad/soft /workspace/aura-pad/scripts /tmp/ap/
cd /tmp/ap && bash scripts/build_c.sh --install /tmp/inst >/dev/null
export PATH=/tmp/inst/bin:$PATH
if command -v docker >/dev/null; then echo "NATIVE_HAS_DOCKER"; fi
aura-pad --where
mkdir -p /tmp/t
for sc in open new unsaved emergency vi; do timeout 180 python3 scripts/cli_pty.py $sc /tmp/t/$sc.txt -- aura-pad /tmp/t/$sc.txt; done
IN
  cat "$OUT/native.txt"
  grep -q '^mode=native$' "$OUT/native.txt" && ! grep -q NATIVE_HAS_DOCKER "$OUT/native.txt" \
    && [[ "$(grep -c '^CLI_PTY_OK ' "$OUT/native.txt")" == 5 ]] \
    || { echo "smoke_cli: native pty in the dev container" >&2; exit 1; }
  echo "smoke_cli: CLI_PTY_OK mode=native-box (dev container, no docker inside)"
else
  echo "CLI_NATIVE_BOX_SKIP reason=no docker"
fi
echo PAD_CLI_OK
