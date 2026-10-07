#!/usr/bin/env bash
# M6 "加c": Soft dump -> thin C blit. Soft owns the editor; C only draws.
#   1. paren balance of Soft view/keys/play + M6 files      -> PAREN_OK
#   2. Soft tests (m6_test.aura, >= 50 checks)              -> PAD_M6_TEST_OK
#   3. Soft edit+HL+jump smoke writes out/m6.snap           -> PAD_M6_OK
#   4. host model rebuilds out/m6.snap byte for byte        -> PAD_M6_MODEL_OK
#   5. build C (host cc, or PAD_C_DOCKER=1 in the dev image) -> out/c/*
#   6. thin guard: no editor/HL/keymap words in c/*          -> PAD_C_THIN_OK
#   7. pad_view: file blit == golden (plain + ANSI), stream (last block wins),
#      fail-closed fixtures exit 1, truncated tail keeps last
#   8. soft_play: scripted key bytes -> Soft -> SNAP stream -> C blit; and
#      pad_play --final drives the same Soft child (host build only)
# Ends with PAD_C_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
mkdir -p "$ROOT/out/c"
FX="$ROOT/c/fixtures"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/view.aura "$ROOT"/soft/pad/keys.aura \
  "$ROOT"/soft/pad/play.aura "$ROOT"/soft/pad/m6_*.aura

soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

echo "smoke_c: m6 Soft tests"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m6_test.aura \
  >"$ROOT/out/m6_test.txt" 2>"$ROOT/out/m6_test.err"
T="$ROOT/out/m6_test.txt"
grep -E '^TESTS ' "$T" || true
if ! grep -q '^PAD_M6_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m6_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m6_test.err" >&2 || true
  echo "smoke_c: PAD_M6_TEST_FAIL" >&2
  exit 1
fi
checks=$(sed -n 's/^TESTS checks=\([0-9]*\) fail=0$/\1/p' "$T")
if [[ -z "$checks" || "$checks" -lt 50 ]]; then
  echo "smoke_c: too few checks (${checks:-none})" >&2
  exit 1
fi
for want in 'T MARKS_HELLO=' 'T LC_CLAMP=2:9 OK' 'T KEY_UP=prev-line OK' \
            'T PLAY_GOTO_SAY=jumped to where hello is born OK' \
            'T PLAY_TEXT=(define (hello x) (+ x 1))|(hello 4) OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_c: test missing: $want" >&2; exit 1; }
done
echo "smoke_c: PAD_M6_TEST_OK checks=$checks"

echo "smoke_c: m6 Soft snapshot"
rm -f "$ROOT/out/m6.snap"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m6_smoke.aura \
  >"$ROOT/out/m6_smoke.txt" 2>"$ROOT/out/m6_smoke.err"
S="$ROOT/out/m6_smoke.txt"
grep -E '^(VIEW|REJECT|SNAPFILE|JUMP|PAD_M6)' "$S" || true
fail=0
for want in 'VIEW keys=3 rej=1 cursor=2:1 name=hello' \
            'reason=no-line cmd=next-line' 'SNAPFILE path=/workspace/aura-pad/out/m6.snap bytes=' \
            'JUMP cmd=goto-def point=9 refs=1' 'PAD_M6_OK'; do
  grep -qF -- "$want" "$S" || { echo "smoke_c: missing: $want" >&2; fail=1; }
done
if grep -q '_FAIL\|WANT=' "$S" || soft_errs "$S" "$ROOT/out/m6_smoke.err"; then fail=1; fi
test -s "$ROOT/out/m6.snap" || { echo "smoke_c: Soft wrote no out/m6.snap" >&2; fail=1; }
[[ "$fail" -eq 0 ]] || { cat "$ROOT/out/m6_smoke.err" >&2 || true; exit 1; }
echo "smoke_c: PAD_M6_OK"

python3 "$ROOT/scripts/snap_model.py" --check "$ROOT/out/m6.snap" >"$ROOT/out/m6_model.txt"
tail -1 "$ROOT/out/m6_model.txt"
grep -q '^PAD_M6_MODEL_OK$' "$ROOT/out/m6_model.txt" || { cat "$ROOT/out/m6_model.txt" >&2; exit 1; }
cmp -s "$ROOT/out/m6.snap" "$FX/good.snap" \
  || { echo "smoke_c: Soft snapshot drifted from c/fixtures/good.snap" >&2; exit 1; }

echo "smoke_c: build thin C viewport"
bash "$ROOT/scripts/build_c.sh"
if [[ "${PAD_C_DOCKER:-0}" == "1" ]] || ! command -v cc >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
  CRUN=("${DOCKER[@]}" run --rm -i --entrypoint /usr/local/bin/gosu
        -v "$ROOT:/workspace/aura-pad" -w /workspace/aura-pad "$IMG" dev)
  VIEW=/workspace/aura-pad/out/c/pad_view
  CFX=/workspace/aura-pad/c/fixtures
  HOSTPLAY=0
else
  CRUN=()
  VIEW="$ROOT/out/c/pad_view"
  CFX="$FX"
  HOSTPLAY=1
fi
view() { "${CRUN[@]}" "$VIEW" "$@"; }

echo "smoke_c: error log rotation"
if [[ "$HOSTPLAY" == 1 ]]; then
  "$ROOT/out/c/errlog_test"
else
  "${CRUN[@]}" /workspace/aura-pad/out/c/errlog_test
fi
echo "smoke_c: ERRLOG_OK"

# Thin guard: the viewport must not know editor commands, HL words, kid
# words, or key meanings. Those live in Soft (edit/hl/jump/keys.aura).
if grep -nE '"(define|lambda|query:|mutate:|left|right|home|end|back|undo|yank|enter|quit|goto-def|jump-back|find-refs|kill-line|open-line|prev-line|next-line)"' \
     "$ROOT"/c/*.c "$ROOT"/c/*.h \
   || grep -niE '"[^"]*(born|jump|no line|nothing to)[^"]*"' "$ROOT"/c/*.c \
   || grep -nE 'kb\[[^]]*\] *(==|!=|<|>)' "$ROOT/c/pad_play.c" "$ROOT/c/play_loop.c" "$ROOT/c/aura_pad.c"; then
  echo "smoke_c: C viewport grew editor logic (see above)" >&2
  exit 1
fi
echo "smoke_c: PAD_C_THIN_OK"

echo "smoke_c: C blit"
view --plain --stats "$CFX/good.snap" >"$ROOT/out/c/good.plain" 2>"$ROOT/out/c/good.stats"
cat "$ROOT/out/c/good.plain"
cat "$ROOT/out/c/good.stats"
cmp -s "$ROOT/out/c/good.plain" "$FX/good.plain" || { diff "$FX/good.plain" "$ROOT/out/c/good.plain" >&2; exit 1; }
grep -qF 'PAD_C_BLIT rows=3 cells=66 cursor=2:1 marks=15 snaps=1 rejected=0 mode=plain' "$ROOT/out/c/good.stats" \
  || { echo "smoke_c: bad blit stats" >&2; exit 1; }
view --ansi "$CFX/good.snap" >"$ROOT/out/c/good.ansi"
# Golden keeps ESC as the two chars "\e" so the repo holds no control bytes.
sed 's/\x1b/\\e/g' "$ROOT/out/c/good.ansi" >"$ROOT/out/c/good.ansi.txt"
cmp -s "$ROOT/out/c/good.ansi.txt" "$FX/good.ansi.txt" || { echo "smoke_c: ANSI blit drifted" >&2; exit 1; }
esc=$'\033'
for want in "${esc}[0;1;35mdefine" "${esc}[0;0;1;4mhello" "${esc}[0;0;4;7mh" \
            "${esc}[0;2;37m; hi" "${esc}[1;33mthere is no line there"; do
  grep -qF -- "$want" "$ROOT/out/c/good.ansi" || { echo "smoke_c: ANSI run missing" >&2; exit 1; }
done
echo "smoke_c: blit file plain+ansi OK"

# Stream: Soft stdout (logs + two SNAP blocks) piped straight into C.
view --plain --stats <"$S" >"$ROOT/out/c/stream.plain" 2>"$ROOT/out/c/stream.stats"
cat "$ROOT/out/c/stream.stats"
grep -qF 'cursor=0:9 marks=15 snaps=2 rejected=0' "$ROOT/out/c/stream.stats" \
  || { echo "smoke_c: stream did not keep the last block" >&2; exit 1; }
grep -qF 'say: hello is born here' "$ROOT/out/c/stream.plain" || exit 1

# Fail closed: a bad or truncated block is never drawn.
for bad in truncated badlen badcursor badletter noise; do
  f="$CFX/$bad.snap"; [[ "$bad" == noise ]] && f="$CFX/noise.txt"
  if view --plain "$f" >"$ROOT/out/c/$bad.out" 2>"$ROOT/out/c/$bad.err"; then
    echo "smoke_c: $bad was drawn" >&2; exit 1
  fi
  [[ ! -s "$ROOT/out/c/$bad.out" ]] || { echo "smoke_c: $bad drew output" >&2; exit 1; }
done
view --plain --stats "$CFX/tail.snap" >/dev/null 2>"$ROOT/out/c/tail.stats"
grep -qF 'cursor=2:1 marks=15 snaps=1 rejected=1' "$ROOT/out/c/tail.stats" \
  || { echo "smoke_c: truncated tail did not keep last block" >&2; exit 1; }
echo "smoke_c: fail-closed OK"

# Soft play: key bytes -> Soft keymap/gate -> SNAP stream -> C blit.
KEYS=(27 91 66 5 127 127 52 41 1 27 91 67 7 2 18 9 17)
: >"$ROOT/out/play.in"
for k in "${KEYS[@]}"; do echo "IN $k" >>"$ROOT/out/play.in"; done
bash "$ROOT/scripts/soft_play.sh" <"$ROOT/out/play.in" >"$ROOT/out/play.txt" 2>"$ROOT/out/play.err"
if soft_errs "$ROOT/out/play.txt" "$ROOT/out/play.err"; then cat "$ROOT/out/play.err" >&2; exit 1; fi
view --plain --stats <"$ROOT/out/play.txt" >"$ROOT/out/c/play.plain" 2>"$ROOT/out/c/play.stats"
cat "$ROOT/out/c/play.plain"
cat "$ROOT/out/c/play.stats"
grep -qF 'cursor=1:1 marks=10 snaps=13 rejected=0' "$ROOT/out/c/play.stats" || { echo "smoke_c: play stream" >&2; exit 1; }
grep -qF '  2 | (hello 4)' "$ROOT/out/c/play.plain" || exit 1
grep -qF 'say: that key does nothing yet' "$ROOT/out/c/play.plain" || exit 1
grep -qF '== aura pad (Soft) keys=11 no=1 ==' "$ROOT/out/c/play.plain" || exit 1
echo "smoke_c: soft_play stream -> pad_view OK"

if [[ "$HOSTPLAY" == "1" ]]; then
  printf '\033[B\005\177\1774)\001\033[C\007\002\022\t\021' \
    | (cd "$ROOT" && ./out/c/pad_play --plain --final --stats) \
      >"$ROOT/out/c/pad_play.plain" 2>"$ROOT/out/c/pad_play.stats"
  grep -E '^PAD_C_PLAY' "$ROOT/out/c/pad_play.stats"
  grep -qF 'PAD_C_PLAY keys=17 snaps=13 rejected=0 cursor=1:1' "$ROOT/out/c/pad_play.stats" \
    || { cat "$ROOT/out/c/pad_play.stats" >&2; echo "smoke_c: pad_play" >&2; exit 1; }
  cmp -s "$ROOT/out/c/pad_play.plain" "$ROOT/out/c/play.plain" \
    || { echo "smoke_c: pad_play frame != soft_play stream frame" >&2; exit 1; }
  echo "smoke_c: pad_play (C forwards bytes, Soft decides) OK"
else
  echo "smoke_c: PAD_C_PLAY_SKIP reason=docker-build (no nested docker)"
fi

echo "smoke_c: PAD_C_OK"
