#!/usr/bin/env bash
# Aura-native perf round (docs/perf-aura.md).
#   1. paren balance of play_in/play + aura_perf_test/aura_facts   -> PAREN_OK
#   2. Soft tests (aura_perf_test.aura): with PAD_DEFER the stream minus
#      its early frames == the stream without deferral, every early frame
#      changes only row l and that row is already final, early frames
#      taken                                                 -> PAD_AURA_PERF_TEST_OK
#   3. Aura surfaces the doc relies on / rejects (aura_facts.aura): no
#      workspace in file mode, fiber spawn/join, mutate:rebind,
#      ast:snapshot/restore, relower stats                   -> PAD_AURA_FACTS_OK
#   4. play.aura with PAD_DEFER=1 on a random batched key stream: frames
#      minus early ones == PAD_DEFER unset, byte for byte    -> DEFER_STREAM_OK
#   5. C tty update over the deferred stream: pad_view --replay leaves the
#      same screen as --replay-full after every frame       -> TERM_MODEL_OK
# Ends with PAD_AURA_PERF_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/aura-perf"
mkdir -p "$OUT" "$ROOT/out/c"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/play_in.aura "$ROOT"/soft/pad/play.aura \
  "$ROOT"/soft/pad/aura_perf_test.aura "$ROOT"/soft/pad/aura_facts.aura

for t in aura_perf_test:PAD_AURA_PERF_TEST_OK aura_facts:PAD_AURA_FACTS_OK; do
  f="${t%%:*}"; ok="${t#*:}"
  echo "smoke_aura_perf: $f"
  bash "$ROOT/scripts/run_soft.sh" "/workspace/aura-pad/soft/pad/$f.aura" \
    </dev/null >"$OUT/$f.txt" 2>"$OUT/$f.err"
  grep -E '^(T |APSTATS|APFACTS|TESTS|PAD_AURA)' "$OUT/$f.txt" | grep -v '^T GAP' || true
  if ! grep -q "^$ok\$" "$OUT/$f.txt" || grep -q 'WANT=' "$OUT/$f.txt" \
     || soft_errs "$OUT/$f.txt" "$OUT/$f.err"; then
    cat "$OUT/$f.err" >&2 || true
    echo "smoke_aura_perf: $f failed" >&2; exit 1
  fi
done

echo "smoke_aura_perf: PAD_DEFER=1 stream == plain stream (minus early frames)"
python3 - "$OUT" <<'PY'
import random, sys
out = sys.argv[1]
random.seed(23)
setup = ["IN 27", "IN 91", "IN 66"] * 4 + ["IN 5"]
pool = [[97], [98], [32], [34], [34], [34], [40], [41], [49], [59], [92],
        [127], [127], [27, 91, 68], [27, 91, 67], [27, 91, 65], [27, 91, 66],
        [1], [5], [13], [11], [25], [31]]
keys = [random.choice(pool) for _ in range(240)]
lines = setup + ["IN " + " ".join(map(str, k)) for k in keys] + ["QUIT"]
open(f"{out}/defer.in", "w").write("\n".join(lines) + "\n")
PY
for v in 0 1; do
  PAD_DEFER=$v bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/play.aura \
    <"$OUT/defer.in" >"$OUT/defer_$v.out" 2>"$OUT/defer_$v.err"
  if soft_errs "$OUT/defer_$v.out" "$OUT/defer_$v.err"; then
    cat "$OUT/defer_$v.err" >&2; echo "smoke_aura_perf: play PAD_DEFER=$v errors" >&2; exit 1
  fi
done
python3 - "$OUT" <<'PY' | tee "$OUT/defer_stream.txt"
import sys
out = sys.argv[1]
def frames(p):
    s = open(p).read()
    fs = s.split("END\n")
    return [f + "END\n" for f in fs[:-1]], fs[-1]
ref, rt = frames(f"{out}/defer_0.out")
got, gt = frames(f"{out}/defer_1.out")
def head(f, key):
    for ln in f.split("\n"):
        if ln.startswith(key):
            return ln
    return None
# an early frame is followed by the exact frame for the same key: same
# TITLE (key count) and CURSOR, and it marks only the cursor row dirty
kept, early = [], 0
for i, f in enumerate(got):
    nx = got[i + 1] if i + 1 < len(got) else None
    if (nx is not None and head(f, "TITLE") == head(nx, "TITLE")
            and head(f, "CURSOR") == head(nx, "CURSOR")
            and head(f, "DIRTY") == "DIRTY lines=" + head(f, "CURSOR").split("line=")[1].split()[0]):
        early += 1
        continue
    kept.append(f)
ok = kept == ref and rt == gt and early >= 5 and len(ref) >= 200
print(f"{'DEFER_STREAM_OK' if ok else 'DEFER_STREAM_FAIL'} frames={len(ref)} deferred={len(got)} early={early}")
PY
grep -q '^DEFER_STREAM_OK ' "$OUT/defer_stream.txt" || { echo "smoke_aura_perf: deferred stream differs" >&2; exit 1; }

echo "smoke_aura_perf: C tty update over the deferred stream"
if command -v cc >/dev/null 2>&1; then
  cc -std=c11 -O2 -Wall -Wextra -pedantic "$ROOT/c/snap.c" "$ROOT/c/pad_view.c" -o "$ROOT/out/c/pad_view_ap"
  V=("$ROOT/out/c/pad_view_ap")
else
  bash "$ROOT/scripts/build_c.sh" >/dev/null
  V=("$ROOT/out/c/pad_view")
fi
"${V[@]}" --replay "$OUT/defer_1.out" >"$OUT/replay_diff.bin"
"${V[@]}" --replay-full "$OUT/defer_1.out" >"$OUT/replay_full.bin"
python3 "$ROOT/scripts/term_model.py" "$OUT/replay_diff.bin" "$OUT/replay_full.bin" | tee "$OUT/term_model.txt"
grep -q '^TERM_MODEL_OK ' "$OUT/term_model.txt" || { echo "smoke_aura_perf: tty update drifted" >&2; exit 1; }

echo "smoke_aura_perf: PAD_AURA_PERF_OK"
