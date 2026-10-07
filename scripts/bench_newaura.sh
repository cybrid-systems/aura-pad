#!/usr/bin/env bash
# New-Soft A/B (docs/perf.md "Soft 18b48dc"): same pty harness as
# scripts/bench_cli.sh (scripts/latency_pty.py, 12-row *lc-big-page*,
# cursor at the end of row 6, dev:v1.0.9), aura-pad --ansi (no FILE),
# rows interleaved round by round (order rotates):
#   old    : BENCH_TIP tree (default HEAD) on the old Soft binary
#            (BENCH_OLD_BIN, default build/aura.c69e644)
#   new    : BENCH_TIP tree on the new Soft binary (BENCH_NEW_BIN,
#            default build/aura.18b48dc); char-ready? exists there, so the
#            early frame and settle skip are on by themselves
#   native : this tree on the new binary (char-ready? called directly)
# Keys: insert (a / backspace), cursor (left / right), string (" /
# backspace: opens and closes a string above five rows). first = first
# byte, done = last byte before 60 ms of quiet.
# Output: out/newaura/bench.txt, BENCH_NEW per-row medians of per-run medians.
# Not a smoke: timing on a shared box.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
N="${BENCH_N:-60}"
ROUNDS="${BENCH_ROUNDS:-6}"
TIP="${BENCH_TIP:-HEAD}"
OLD_BIN="${BENCH_OLD_BIN:-/workspace/aura-grok/build/aura.c69e644}"
NEW_BIN="${BENCH_NEW_BIN:-/workspace/aura-grok/build/aura.18b48dc}"
OUT="$ROOT/out/newaura"
mkdir -p "$OUT/tip"
if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
rm -rf "$OUT/tip" && mkdir -p "$OUT/tip"
git -C "$ROOT" archive "$TIP" | tar -x -C "$OUT/tip"
run_box() { # tree bin name
  "${DOCKER[@]}" run --rm -i --entrypoint bash \
    -v "${AURA_SRC}:/workspace/aura-grok" -v "$1:/workspace/aura-pad" \
    -w /workspace/aura-pad \
    -e AURA_PATH=/workspace/aura-grok/lib -e AURA_PIPELINE_STRICT=0 -e AURA_SANDBOX=off \
    -e AURA_BIN="$2" -e PAD_PAGE=big -e N="$N" -e NAME="$3" "$IMG" -s <<'IN'
set -euo pipefail
cd /workspace/aura-pad
B=/tmp/bench; mkdir -p $B
cc -std=c11 -O2 -Wall -Wextra c/snap.c c/play_loop.c c/aura_pad.c -o $B/aura-pad
export AURA_PAD_HOME=/workspace/aura-pad
DOWN6=1b5b42,1b5b42,1b5b42,1b5b42,1b5b42,1b5b42
python3 scripts/latency_pty.py --n "$N" --name "$NAME" --setup-keys "$DOWN6,05" --startup-quiet 2500 \
  --pairs 61:7f,1b5b44:1b5b43,22:7f --labels insert,cursor,string -- $B/aura-pad --ansi 2>&1 | grep -E '^LATENCY'
IN
}
row() { case "$1" in
  old) run_box "$OUT/tip" "$OLD_BIN" old ;;
  new) run_box "$OUT/tip" "$NEW_BIN" new ;;
  native) run_box "$ROOT" "$NEW_BIN" native ;;
esac; }
: >"$OUT/bench.txt"
echo "BENCH_NEW host=$(hostname) nproc=$(nproc) date=$(date -Is) n=$N rounds=$ROUNDS tip=$(git -C "$ROOT" rev-parse --short "$TIP") old=$(basename "$OLD_BIN") new=$(basename "$NEW_BIN") load=\"$(cut -d' ' -f1-3 /proc/loadavg)\"" | tee -a "$OUT/bench.txt"
orders=("old new native" "native old new" "new native old")
for r in $(seq 1 "$ROUNDS"); do
  for x in ${orders[$(( (r - 1) % 3 ))]}; do
    row "$x" | sed "s/^LATENCY /LATENCY round=$r /" | tee -a "$OUT/bench.txt"
  done
done
python3 - "$OUT/bench.txt" <<'PY' | tee -a "$OUT/bench.txt"
import re, statistics, sys
rows = {}
for ln in open(sys.argv[1]):
    if not ln.startswith("LATENCY "):
        continue
    name = re.search(r" name=(\S+)", ln).group(1)
    for lab in ("insert", "cursor", "string"):
        m = re.search(lab + r":n=\d+,first_med_us=(\d+),done_med_us=(\d+),done_p90_us=(\d+),bytes_med=(\d+)", ln)
        if m:
            rows.setdefault((name, lab), []).append(tuple(int(x) for x in m.groups()))
for (name, lab), v in sorted(rows.items()):
    f = statistics.median(x[0] for x in v)
    d = statistics.median(x[1] for x in v)
    print(f"BENCH_NEW row={name} key={lab} runs={len(v)} first_med_ms={f/1000:.2f} done_med_ms={d/1000:.2f} "
          f"per_run_done_ms={','.join(f'{x[1]/1000:.2f}' for x in v)} tty_bytes_med={v[0][3]}")
PY
