#!/usr/bin/env bash
# M7 "snappy pad": line-incremental Soft key path. Soft owns it; C unchanged.
#   1. paren balance of lc.aura / m7_test.aura / perf.aura      -> PAREN_OK
#   2. Soft tests: every cached frame == M6 whole-page oracle   -> PAD_M7_TEST_OK
#   3. Soft play stream (scripted key bytes, incl. an unclosed
#      string fallback): DIRTY sound + tight (host audit)       -> PAD_M7_DIRTY_OK
#      and the same stream still blits through thin C pad_view
#   4. key-path perf: small page PAD_PERF_OK + twelve-line page
#      PAD_M7_PERF_OK (<50 ms/key and >=2x vs the M6 path)
# Ends with PAD_M7_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/lc.aura "$ROOT"/soft/pad/m7_test.aura "$ROOT"/soft/pad/perf.aura \
  "$ROOT"/soft/pad/keys.aura "$ROOT"/soft/pad/jump.aura

echo "smoke_m7: Soft tests (cache frame == whole-page oracle)"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m7_test.aura \
  >"$ROOT/out/m7_test.txt" 2>"$ROOT/out/m7_test.err"
T="$ROOT/out/m7_test.txt"
grep -E '^(TESTS|M7STATS) ' "$T" || true
if ! grep -q '^PAD_M7_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m7_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m7_test.err" >&2 || true
  echo "smoke_m7: PAD_M7_TEST_FAIL" >&2
  exit 1
fi
checks=$(sed -n 's/^TESTS checks=\([0-9]*\) fail=0$/\1/p' "$T")
if [[ -z "$checks" || "$checks" -lt 140 ]]; then
  echo "smoke_m7: too few checks (${checks:-none})" >&2; exit 1
fi
for want in 'T BIG_RETOK_TYPE=15 OK' 'T BIG_RETOK_SPLIT=2 OK' 'T BIG_SP_DIRTY=6 OK' \
            'T BIG_MARKS_DIRTY=0,1,6,10,11 OK' 'T BIG_FULL_ON=1 OK' 'T BIG_FULL_OFF=0 OK' \
            'T LC_TOKS_EQ OK' 'T FRAME_FIRST OK' 'T M6_LC=1:1 OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m7: test missing: $want" >&2; exit 1; }
done
echo "smoke_m7: PAD_M7_TEST_OK checks=$checks"

echo "smoke_m7: Soft play stream -> DIRTY audit"
# down end back back 4 ) | enter, type "(hi 2)" | up x3 home right x2 (onto
# hello) | type '"' at end of row 0 (unclosed string: full fallback) then
# back it out | ctrl-g ctrl-b | ctrl-q
KEYS=(27 91 66 5 127 127 52 41
      13 40 104 105 32 50 41
      27 91 65 27 91 65 1 27 91 67 27 91 67
      5 34 120 127 127
      1 27 91 67 7 2 17)
: >"$ROOT/out/m7_play.in"
for k in "${KEYS[@]}"; do echo "IN $k" >>"$ROOT/out/m7_play.in"; done
bash "$ROOT/scripts/soft_play.sh" <"$ROOT/out/m7_play.in" >"$ROOT/out/m7_play.txt" 2>"$ROOT/out/m7_play.err"
if soft_errs "$ROOT/out/m7_play.txt" "$ROOT/out/m7_play.err"; then cat "$ROOT/out/m7_play.err" >&2; exit 1; fi
python3 "$ROOT/scripts/dirty_check.py" "$ROOT/out/m7_play.txt" | tee "$ROOT/out/m7_dirty.txt"
grep -q '^PAD_M7_DIRTY_OK$' "$ROOT/out/m7_dirty.txt" || exit 1

# The same stream through the thin C viewport (unchanged C): last block wins.
if [[ -x "$ROOT/out/c/pad_view" ]] && command -v cc >/dev/null 2>&1; then
  "$ROOT/out/c/pad_view" --plain --stats <"$ROOT/out/m7_play.txt" \
    >"$ROOT/out/c/m7_play.plain" 2>"$ROOT/out/c/m7_play.stats"
  cat "$ROOT/out/c/m7_play.stats"
  grep -qF 'rejected=0' "$ROOT/out/c/m7_play.stats" || { echo "smoke_m7: C rejected a Soft block" >&2; exit 1; }
  grep -qF '  3 | (hi 2)' "$ROOT/out/c/m7_play.plain" || { echo "smoke_m7: C frame" >&2; exit 1; }
  echo "smoke_m7: C pad_view blits the M7 stream OK"
else
  echo "smoke_m7: PAD_M7_C_SKIP reason=no-host-pad_view"
fi

echo "smoke_m7: key-path perf"
bash "$ROOT/scripts/smoke_perf.sh"
echo "smoke_m7: PAD_M7_OK"
