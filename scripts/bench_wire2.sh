#!/usr/bin/env bash
# Wire v2 A/B latency (docs/perf.md "wire v2"): the same pty harness as
# scripts/bench_editors.sh (scripts/latency_pty.py, 12-row *lc-big-page*,
# cursor at the end of row 6, PAD_PAGE=big, dev:v1.0.9 container), pad
# only, three rows interleaved round by round so a CPU neighbour (the
# aura-build-burn container) hits all of them alike:
#   pad-w1 : this tree, pad_play --wire1 (SNAP v1, every row each frame)
#   pad-w2 : this tree, pad_play --wire2 (SNAP v2, DIRTY rows only)
#   pad-tip: BENCH_TIP=<rev> (default 6b51057, before wire v2) built from
#            git archive in out/wire2/tip, run the same way (sanity "before")
# Order of w1/w2 alternates per round. Output: out/wire2/bench.txt
# (LATENCY lines tagged round=) and the per-row median of the per-run
# medians (BENCH_W2 lines). Not a smoke: timing on a shared box.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
N="${BENCH_N:-60}"
ROUNDS="${BENCH_ROUNDS:-6}"
TIP="${BENCH_TIP-6b51057}"
OUT="$ROOT/out/wire2"
mkdir -p "$OUT/bench"
if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
if [[ -n "$TIP" ]]; then
  # extract over any earlier copy (the container leaves root-owned
  # out/bench/ files there; tracked files are rewritten from $TIP)
  mkdir -p "$OUT/tip"
  git -C "$ROOT" archive "$TIP" | tar -x -C "$OUT/tip"
fi
run_box() { # tree rows...
  local tree="$1"; shift
  "${DOCKER[@]}" run --rm -i --entrypoint bash \
    -v "${AURA_SRC}:/workspace/aura-grok" -v "${tree}:/workspace/aura-pad" \
    -w /workspace/aura-pad \
    -e AURA_PATH=/workspace/aura-grok/lib -e AURA_PIPELINE_STRICT=0 -e AURA_SANDBOX=off \
    -e AURA_BIN=/workspace/aura-grok/build/aura -e PAD_PAGE=big -e N="$N" \
    -e ROWS="$*" "$IMG" -s <<'IN'
set -euo pipefail
cd /workspace/aura-pad
mkdir -p out/bench
cc -std=c11 -O2 -Wall -Wextra c/snap.c $(ls c/play_loop.c 2>/dev/null) c/pad_play.c -o out/bench/pad_play_w2b
DOWN6=1b5b42,1b5b42,1b5b42,1b5b42,1b5b42,1b5b42
for row in $ROWS; do
  case "$row" in
    pad-w1) F=(--wire1) ;; pad-w2) F=(--wire2) ;; *) F=() ;;
  esac
  python3 scripts/latency_pty.py --n "$N" --name "$row" --setup-keys "$DOWN6,05" --startup-quiet 2500 -- \
    out/bench/pad_play_w2b --ansi "${F[@]}" scripts/bench_soft_play.sh
done 2>&1 | grep -E '^LATENCY'
IN
}
: >"$OUT/bench.txt"
echo "BENCH_W2 host=$(hostname) nproc=$(nproc) date=$(date -Is) n=$N rounds=$ROUNDS tip=${TIP:-none} load=\"$(cut -d' ' -f1-3 /proc/loadavg)\"" | tee -a "$OUT/bench.txt"
for r in $(seq 1 "$ROUNDS"); do
  if (( r % 2 )); then rows="pad-w1 pad-w2"; else rows="pad-w2 pad-w1"; fi
  run_box "$ROOT" $rows | sed "s/^LATENCY /LATENCY round=$r /" | tee -a "$OUT/bench.txt"
  if [[ -n "$TIP" ]]; then
    run_box "$OUT/tip" pad-tip | sed "s/^LATENCY /LATENCY round=$r /" | tee -a "$OUT/bench.txt"
  fi
done
python3 - "$OUT/bench.txt" <<'PY' | tee -a "$OUT/bench.txt"
import re, statistics, sys
rows = {}
for ln in open(sys.argv[1]):
    if not ln.startswith("LATENCY "):
        continue
    name = re.search(r" name=(\S+)", ln).group(1)
    for lab in ("insert", "cursor"):
        m = re.search(lab + r":n=\d+,first_med_us=\d+,done_med_us=(\d+),done_p90_us=(\d+),bytes_med=(\d+)", ln)
        if m:
            rows.setdefault((name, lab), []).append(tuple(int(x) for x in m.groups()))
for (name, lab), v in sorted(rows.items()):
    med = statistics.median(x[0] for x in v)
    p90 = statistics.median(x[1] for x in v)
    print(f"BENCH_W2 row={name} key={lab} runs={len(v)} done_med_ms={med/1000:.2f} "
          f"p90_med_ms={p90/1000:.2f} per_run_ms={','.join(f'{x[0]/1000:.2f}' for x in v)} tty_bytes_med={v[0][2]}")
PY
