#!/usr/bin/env bash
# aura-pad CLI latency A/B (docs/perf.md "aura-pad one command"): same pty
# harness as scripts/bench_wire2.sh (scripts/latency_pty.py, 12-row
# *lc-big-page*, cursor at the end of row 6, dev:v1.0.9 container), rows
# interleaved round by round (order rotates) so a CPU neighbour hits all
# of them alike:
#   pp-tip   : BENCH_TIP=<rev> (default 0900d89, before aura-pad) pad_play
#              --ansi scripts/bench_soft_play.sh, PAD_PAGE=big ("before")
#   pp       : this tree, the same pad_play command
#   cli      : this tree, aura-pad --ansi (no FILE, PAD_PAGE=big; aura
#              exec'd directly by the C launcher, no bash / stdbuf)
#   cli-file : this tree, aura-pad --ansi big.txt (the same 12 rows as a
#              file, file mode: ctrl-x ctrl-s / ctrl-q keys live)
# Plus startup: spawn -> first full frame ("say:" painted) for pp and
# cli-file, BENCH_START lines. Output: out/cli/bench.txt with LATENCY
# lines tagged round= and BENCH_CLI per-row medians of per-run medians.
# Not a smoke: timing on a shared box.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
N="${BENCH_N:-60}"
ROUNDS="${BENCH_ROUNDS:-6}"
TIP="${BENCH_TIP-0900d89}"
OUT="$ROOT/out/cli"
mkdir -p "$OUT/bench"
if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
if [[ -n "$TIP" ]]; then
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
B=/tmp/bench; mkdir -p $B
cc -std=c11 -O2 -Wall -Wextra c/snap.c $(ls c/play_loop.c 2>/dev/null) c/pad_play.c -o $B/pad_play
if [[ -f c/aura_pad.c ]]; then
  cc -std=c11 -O2 -Wall -Wextra c/snap.c c/play_loop.c c/aura_pad.c -o $B/aura-pad
fi
printf '%s\n' '(define (hello x) (+ x 1))' '(define (bye y) (hello y))' \
  '(define (add a b) (+ a b))' '; kids write stories here' '(define pet "cat")' \
  '(define (greet n) (add n 1))' '(hello 3)' '(bye 4)' '(greet (add 1 2))' \
  '(display pet)' '(query:find hello)' '(hello (bye 5))' > $B/big.txt
export AURA_PAD_HOME=/workspace/aura-pad
DOWN6=1b5b42,1b5b42,1b5b42,1b5b42,1b5b42,1b5b42
for row in $ROWS; do
  case "$row" in
    pp|pp-tip) C=($B/pad_play --ansi scripts/bench_soft_play.sh) ;;
    cli) C=($B/aura-pad --ansi) ;;
    cli-file) C=($B/aura-pad --ansi $B/big.txt) ;;
    start-pp|start-cli-file)
      if [[ $row == start-pp ]]; then C=($B/pad_play --ansi scripts/bench_soft_play.sh)
      else C=($B/aura-pad --ansi $B/big.txt); fi
      python3 - "$row" "${C[@]}" <<'PY'
import os, pty, select, statistics, sys, time, signal
name, cmd = sys.argv[1], sys.argv[2:]
ts = []
for i in range(7):
    t0 = time.monotonic()
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(cmd[0], cmd)
    buf = b""
    while b"say:" not in buf and time.monotonic() - t0 < 20:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try: buf += os.read(fd, 65536)
            except OSError: break
    ts.append(time.monotonic() - t0)
    os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0); os.close(fd)
print(f"START name={name} n={len(ts)} first_frame_med_ms={statistics.median(ts)*1000:.0f} "
      f"min_ms={min(ts)*1000:.0f} max_ms={max(ts)*1000:.0f}")
PY
      continue ;;
  esac
  python3 scripts/latency_pty.py --n "$N" --name "$row" --setup-keys "$DOWN6,05" --startup-quiet 2500 -- \
    "${C[@]}"
done 2>&1 | grep -E '^(LATENCY|START)'
IN
}
: >"$OUT/bench.txt"
echo "BENCH_CLI host=$(hostname) nproc=$(nproc) date=$(date -Is) n=$N rounds=$ROUNDS tip=${TIP:-none} load=\"$(cut -d' ' -f1-3 /proc/loadavg)\"" | tee -a "$OUT/bench.txt"
orders=("pp cli cli-file" "cli-file pp cli" "cli cli-file pp")
for r in $(seq 1 "$ROUNDS"); do
  rows="${orders[$(( (r - 1) % 3 ))]}"
  if [[ -n "$TIP" ]] && (( r % 2 )); then
    run_box "$OUT/tip" pp-tip | sed "s/^LATENCY /LATENCY round=$r /" | tee -a "$OUT/bench.txt"
  fi
  run_box "$ROOT" $rows | sed "s/^LATENCY /LATENCY round=$r /" | tee -a "$OUT/bench.txt"
  if [[ -n "$TIP" ]] && ! (( r % 2 )); then
    run_box "$OUT/tip" pp-tip | sed "s/^LATENCY /LATENCY round=$r /" | tee -a "$OUT/bench.txt"
  fi
done
run_box "$ROOT" start-pp start-cli-file | sed "s/^START /BENCH_START /" | tee -a "$OUT/bench.txt"
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
    print(f"BENCH_CLI row={name} key={lab} runs={len(v)} done_med_ms={med/1000:.2f} "
          f"p90_med_ms={p90/1000:.2f} per_run_ms={','.join(f'{x[0]/1000:.2f}' for x in v)} tty_bytes_med={v[0][2]}")
PY
