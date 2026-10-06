#!/usr/bin/env bash
# Wire v2 (docs/DESIGN.md §7, docs/perf.md): SNAP v2 pad carries only the
# rows Soft marked DIRTY; C rebuilds the rest from the frame it holds or
# drops the block and asks for a full frame. C never picks rows.
#   1. paren balance of wire2/keys/play_in/play                 -> PAREN_OK
#   2. C builds (-Werror, ASan/UBSan) and stays thin            -> PAD_C_THIN_OK
#   3. v2 fail-closed fixtures: wrong base, delta before any base,
#      after a v1 frame or after a dropped delta, full frame missing a
#      row, duplicate / out-of-range R, body= mismatch, new row not sent,
#      bad cursor -> dropped; the last good frame stays     -> W2_FIXTURES_OK
#   4. pad_play --wire2 with a fake Soft that sends a bad delta: C asks
#      "WIRE 2 FULL" once, then draws the full frame        -> W2_ASK_OK
#   5. play.aura v1 vs v2 on the same keys (start page; big page random
#      edits; PAD_DEFER=1 early frames; settle skip; mid-stream
#      "WIRE 2 FULL" / "WIRE 1" / "WIRE 2"): v2 rebuilds to the v1 frames
#      one for one, C replay-full bytes equal per frame, v2 cell-diff ==
#      full repaint (term_model), rebuilt DIRTY sound      -> WIRE2_CHECK_OK
#   6. host pad_play --wire2 --final == v1 frame, rejected=0  -> W2_PLAY_OK
# Ends with PAD_WIRE2_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/wire2/smoke"
FX="$OUT/fx"
rm -rf "$OUT"; mkdir -p "$OUT" "$FX" "$ROOT/out/c"
soft_errs() { grep -qiE 'error:|unbound variable' "$@"; }

python3 "$ROOT/scripts/paren_check.py" "$ROOT"/soft/pad/wire2.aura "$ROOT"/soft/pad/keys.aura \
  "$ROOT"/soft/pad/play_in.aura "$ROOT"/soft/pad/play.aura

# 2. C: host build with ASan for the fixtures, plain build after
if ! command -v cc >/dev/null 2>&1; then echo "smoke_wire2: needs host cc" >&2; exit 1; fi
PAD_C_ASAN=1 bash "$ROOT/scripts/build_c.sh" >/dev/null
if grep -nE '"(define|lambda|query:|mutate:|left|right|home|end|back|undo|yank|enter|quit|goto-def|jump-back|find-refs|kill-line|open-line|prev-line|next-line)"' \
     "$ROOT"/c/*.c "$ROOT"/c/*.h \
   || grep -niE '"[^"]*(born|jump|no line|nothing to)[^"]*"' "$ROOT"/c/*.c \
   || grep -nE 'kb\[[^]]*\] *(==|!=|<|>)' "$ROOT/c/pad_play.c"; then
  echo "smoke_wire2: C viewport grew editor logic (see above)" >&2; exit 1
fi
echo "smoke_wire2: PAD_C_THIN_OK"
VIEW="$ROOT/out/c/pad_view"

# 3. fixtures: name accepted rejected expected-final (v1 twin rendered)
python3 - "$FX" <<'PY'
import sys
fx = sys.argv[1]
L = "LEGEND K=magic-word S=name\n"
def head(title, cl, cc):
    return f"TITLE {title}\nCURSOR line={cl} col={cc}\nSAY hi\n" + L
def row(t, h=None, m=None):
    return f"T {t}\nH {h or 'S' * len(t)}\nM {m or '.' * len(t)}\n"
def body(rows):
    return sum(3 * len(t) + 9 for t in rows)
A = ["(hello 1)", "(world 2)"]
B = ["(hello 1)", "(world 22)"]
def full(gen, rows, title="f", cl=0, cc=0, skip=None, extra="", bodyfix=0):
    s = f"SNAP v2 pad\nGEN {gen} base=-\n" + head(title, cl, cc)
    s += f"ROWS n={len(rows)} body={body(rows) + bodyfix}\n"
    for i, t in enumerate(rows):
        if i != skip:
            s += f"R {i}\n" + row(t)
    return s + extra + "END\n"
def delta(gen, base, rows, sent, title="d", cl=0, cc=0, bodyfix=0, n=None):
    n = len(rows) if n is None else n
    s = f"SNAP v2 pad\nGEN {gen} base={base}\n" + head(title, cl, cc)
    s += f"ROWS n={n} body={body(rows) + bodyfix}\n"
    for i in sent:
        s += f"R {i}\n" + row(rows[i])
    return s + "END\n"
def v1(rows, title, cl=0, cc=0):
    return "SNAP v1 pad\n" + head(title, cl, cc) + f"ROWS n={len(rows)}\n" + "".join(row(t) for t in rows) + "END\n"
C3 = ["(hello 1)", "(world 2)", "(new 3)"]
cases = {
    # name: (stream, accepted, rejected, twin v1 of the final frame or None)
    "w2_good": (full(1, A) + delta(2, 1, B, [1]), 2, 0, v1(B, "d")),
    "w2_reorder": (full(1, A) + delta(2, 1, B, [1, 0]), 2, 0, v1(B, "d")),
    "w2_nobase": (delta(1, 0, B, [1]), 0, 1, None),
    "w2_basemis": (full(1, A) + delta(2, 7, B, [1]), 1, 1, v1(A, "f")),
    "w2_afterbad": (full(1, A) + delta(2, 1, B, [1], bodyfix=1) + delta(3, 2, B, [1]), 1, 2, v1(A, "f")),
    "w2_afterv1": (v1(A, "v") + delta(2, 1, B, [1]) + delta(3, 0, B, [1]), 1, 2, v1(A, "v")),
    "w2_fullmiss": (full(1, A, skip=1), 0, 1, None),
    "w2_dupr": (full(1, A) + delta(2, 1, B, [1, 1]), 1, 1, v1(A, "f")),
    "w2_range": (full(1, A) + delta(2, 1, B, [1]).replace("R 1\n", "R 2\n"), 1, 1, v1(A, "f")),
    "w2_body": (full(1, A) + delta(2, 1, B, [1], bodyfix=-3), 1, 1, v1(A, "f")),
    "w2_grow": (full(1, A) + delta(2, 1, C3, [0]), 1, 1, v1(A, "f")),
    "w2_growok": (full(1, A) + delta(2, 1, C3, [2]), 2, 0, v1(C3, "d")),
    "w2_shrink": (full(1, C3) + delta(2, 1, A, [], n=2), 2, 0, v1(A, "d")),
    "w2_cursor": (full(1, A) + delta(2, 1, B, [1], cl=5), 1, 1, v1(A, "f")),
    "w2_badrow": (full(1, A) + delta(2, 1, B, [1]).replace("H SSSSSSSSSS", "H SSSS"), 1, 1, v1(A, "f")),
    "w2_badgen": (full(1, A) + delta(2, 1, B, [1]).replace("GEN 2 base=1", "GEN x base=1"), 1, 1, v1(A, "f")),
    "w2_recover": (full(1, A) + delta(2, 9, B, [1]) + delta(3, 2, B, [1]) + full(4, B, title="r"), 2, 2, v1(B, "r")),
    "w2_trunc": (full(1, A) + delta(2, 1, B, [1])[:-4], 1, 1, v1(A, "f")),
}
with open(f"{fx}/cases.txt", "w") as idx:
    for name, (s, acc, rej, twin) in cases.items():
        open(f"{fx}/{name}.snap", "w").write("log line before\n" + s)
        if twin:
            open(f"{fx}/{name}.v1", "w").write(twin)
        idx.write(f"{name} {acc} {rej} {1 if twin else 0}\n")
PY
nfx=0
while read -r name acc rej twin; do
  set +e
  "$VIEW" --plain --stats "$FX/$name.snap" >"$FX/$name.plain" 2>"$FX/$name.stats"; rc=$?
  set -e
  if [[ "$acc" == 0 ]]; then
    [[ $rc != 0 ]] && grep -qF "rejected=$rej)" "$FX/$name.stats" \
      || { cat "$FX/$name.stats" >&2; echo "smoke_wire2: fixture $name should be dropped" >&2; exit 1; }
  else
    grep -qF "snaps=$acc rejected=$rej " "$FX/$name.stats" \
      || { cat "$FX/$name.stats" >&2; echo "smoke_wire2: fixture $name want snaps=$acc rejected=$rej" >&2; exit 1; }
    "$VIEW" --plain "$FX/$name.v1" >"$FX/$name.want"
    cmp -s "$FX/$name.plain" "$FX/$name.want" \
      || { diff "$FX/$name.want" "$FX/$name.plain" >&2; echo "smoke_wire2: fixture $name frame" >&2; exit 1; }
  fi
  if grep -qi 'AddressSanitizer\|runtime error' "$FX/$name.stats"; then
    cat "$FX/$name.stats" >&2; exit 1
  fi
  nfx=$((nfx + 1))
done <"$FX/cases.txt"
# replay of a stream with drops: the diff path still equals full repaint
cat "$FX/w2_good.snap" "$FX/w2_basemis.snap" "$FX/w2_recover.snap" >"$FX/mix.snap"
"$VIEW" --replay "$FX/mix.snap" >"$FX/mix_diff.bin"
"$VIEW" --replay-full "$FX/mix.snap" >"$FX/mix_full.bin"
python3 "$ROOT/scripts/term_model.py" "$FX/mix_diff.bin" "$FX/mix_full.bin" >"$FX/mix_term.txt"
grep -q '^TERM_MODEL_OK ' "$FX/mix_term.txt" || { cat "$FX/mix_term.txt" >&2; exit 1; }
echo "smoke_wire2: W2_FIXTURES_OK cases=$nfx"

# 4. pad_play asks for a full frame after a bad delta (fake Soft child)
cat >"$FX/fake_soft.py" <<'PY'
import sys
def out(s):
    sys.stdout.write(s); sys.stdout.flush()
fx = sys.argv[1]
good = open(f"{fx}/w2_good.snap").read()
out(good.split("SNAP v2 pad\n")[0])
first = "SNAP v2 pad\n" + good.split("SNAP v2 pad\n")[1]
out(first)                                                    # gen 1 full
out(open(f"{fx}/w2_basemis.snap").read().split("SNAP v2 pad\n")[2].join(["SNAP v2 pad\n", ""]))  # base=7: dropped
for line in sys.stdin:
    line = line.rstrip("\n")
    sys.stderr.write("fake got " + line + "\n")
    if line == "WIRE 2 FULL":
        rec = open(f"{fx}/w2_recover.snap").read().split("SNAP v2 pad\n")
        out("SNAP v2 pad\n" + rec[4])                          # gen 4 full (title r)
        break
PY
printf '#!/usr/bin/env bash\nexec python3 %q %q\n' "$FX/fake_soft.py" "$FX" >"$FX/fake_soft.sh"
(sleep 3) | "$ROOT/out/c/pad_play" --plain --final --stats --wire2 "$FX/fake_soft.sh" \
  >"$FX/ask.plain" 2>"$FX/ask.stats" || true
cat "$FX/ask.stats"
grep -qF 'fake got WIRE 2 FULL' "$FX/ask.stats" \
  && grep -qE '^PAD_C_PLAY keys=0 snaps=2 rejected=1 .* wire=2 v2=2 v2_rows=4 asks=1$' "$FX/ask.stats" \
  && grep -qF '== r ==' "$FX/ask.plain" \
  || { cat "$FX/ask.plain" >&2; echo "smoke_wire2: pad_play full-frame ask" >&2; exit 1; }
echo "smoke_wire2: W2_ASK_OK"
bash "$ROOT/scripts/build_c.sh" >/dev/null

# 5. play.aura streams, v1 vs v2
python3 - "$OUT" <<'PY'
import random, sys
out = sys.argv[1]
start = [27, 91, 66, 5, 127, 127, 52, 41, 1, 27, 91, 67, 7, 2, 18, 9, 17]
w = lambda name, ls: open(f"{out}/{name}.in", "w").write("\n".join(ls) + "\n")
k_start = [f"IN {b}" for b in start]
w("start_v1", k_start); w("start_v2", ["WIRE 2"] + k_start)
random.seed(29)
setup = ["IN 27 91 66"] * 4 + ["IN 5"]
pool = [[97], [98], [32], [34], [34], [40], [41], [49], [59], [92],
        [127], [127], [27, 91, 68], [27, 91, 67], [27, 91, 65], [27, 91, 66],
        [1], [5], [13], [11], [25], [31]]
keys = setup + ["IN " + " ".join(map(str, random.choice(pool))) for _ in range(200)]
keys += ["IN 27 91 68", "IN 27 91 67", "QUIT"]
w("big_v1", keys); w("big_v2", ["WIRE 2"] + keys)
# mid-stream requests: a full frame on demand, a v1 stretch, back to v2
mid = list(keys[:-1])
mid.insert(60, "WIRE 2 FULL"); mid.insert(120, "WIRE 1"); mid.insert(150, "WIRE 2")
mid.insert(151, "WIRE 2 FULL")
w("mid_v2", ["WIRE 2"] + mid + ["QUIT"])
PY
run_play() { # name env... -> $OUT/name.out
  local name="$1" inp="$2"; shift 2
  env "$@" bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/play.aura \
    <"$OUT/$inp.in" >"$OUT/$name.out" 2>"$OUT/$name.err"
  if soft_errs "$OUT/$name.out" "$OUT/$name.err"; then
    cat "$OUT/$name.err" >&2; echo "smoke_wire2: play $name errors" >&2; exit 1
  fi
}
check() { # v1 v2 tag [min-frames]
  python3 "$ROOT/scripts/wire2_check.py" "$OUT/$1.out" "$OUT/$2.out" --view "$VIEW" \
    --out "$OUT/chk_$3" --min-frames "${4:-2}" --min-v2 2 | tee "$OUT/chk_$3.txt"
  grep -q '^WIRE2_CHECK_OK ' "$OUT/chk_$3.txt" || { echo "smoke_wire2: $3 v2 != v1" >&2; exit 1; }
}
run_play start_v1 start_v1 PAD_DEFER=0
run_play start_v2 start_v2 PAD_DEFER=0
check start_v1 start_v2 start 10
for d in 0 1; do
  run_play big_v1_d$d big_v1 PAD_PAGE=big PAD_DEFER=$d
  run_play big_v2_d$d big_v2 PAD_PAGE=big PAD_DEFER=$d
  check big_v1_d$d big_v2_d$d big_d$d 150
done
python3 "$ROOT/scripts/dirty_check.py" "$OUT/big_v1_d0.out" | tail -1 | tee "$OUT/dirty_v1.txt"
python3 "$ROOT/scripts/dirty_check.py" "$OUT/chk_big_d0/v2_rebuilt.txt" | tail -1 | tee "$OUT/dirty_v2.txt"
cmp -s "$OUT/dirty_v1.txt" "$OUT/dirty_v2.txt" || { echo "smoke_wire2: dirty_check v1/v2 disagree" >&2; exit 1; }
run_play skip_v1 big_v1 PAD_PAGE=big PAD_DEFER=1 PAD_TEST_PENDING=2
run_play skip_v2 big_v2 PAD_PAGE=big PAD_DEFER=1 PAD_TEST_PENDING=2
check skip_v1 skip_v2 skip 100
run_play mid_v2 mid_v2 PAD_PAGE=big PAD_DEFER=0
python3 "$ROOT/scripts/wire2_check.py" "$OUT/big_v1_d0.out" "$OUT/mid_v2.out" --view "$VIEW" \
  --out "$OUT/chk_mid" --min-frames 150 | tee "$OUT/chk_mid.txt"
grep -qE '^WIRE2_CHECK_OK .* requested_full=5 ' "$OUT/chk_mid.txt" \
  || { echo "smoke_wire2: mid-stream WIRE requests" >&2; exit 1; }
echo "smoke_wire2: WIRE2_CHECK_OK (start, big, defer, skip, mid)"

# 6. the real pad_play child: v2 final frame == v1 final frame
KEYS=(27 91 66 5 127 127 52 41 1 27 91 67 7 2 18 9 17)
for k in "${KEYS[@]}"; do printf "\\$(printf '%03o' "$k")"; done >"$OUT/keys.bin"
(cd "$ROOT" && ./out/c/pad_play --plain --final --stats --wire1 <"$OUT/keys.bin") \
  >"$OUT/play_v1.plain" 2>"$OUT/play_v1.stats"
(cd "$ROOT" && ./out/c/pad_play --plain --final --stats --wire2 <"$OUT/keys.bin") \
  >"$OUT/play_v2.plain" 2>"$OUT/play_v2.stats"
grep -E '^PAD_C_PLAY' "$OUT/play_v1.stats" "$OUT/play_v2.stats"
grep -qE '^PAD_C_PLAY keys=17 snaps=13 rejected=0 cursor=1:1 wire=1 v2=0 ' "$OUT/play_v1.stats" \
  && grep -qE '^PAD_C_PLAY keys=17 snaps=14 rejected=0 cursor=1:1 wire=2 v2=13 .* asks=0$' "$OUT/play_v2.stats" \
  && cmp -s "$OUT/play_v1.plain" "$OUT/play_v2.plain" \
  || { echo "smoke_wire2: pad_play --wire2 frame/stats" >&2; exit 1; }
echo "smoke_wire2: W2_PLAY_OK"
echo PAD_WIRE2_OK
