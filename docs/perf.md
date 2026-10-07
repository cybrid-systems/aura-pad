# Aura Pad key latency

Kid pad keys should feel snappier than a sleepy editor — Soft owns the
editor, so the interactive path is Soft gate + apply + SNAP pack (+ thin
C blit). This page publishes measured **ms/key** for the scripted Soft
stream on tip Soft. See [`REQUIREMENTS.md`](REQUIREMENTS.md) §5 and
[`DESIGN.md`](DESIGN.md) §8 for the budget and the honesty rule.

```bash
bash scripts/smoke_perf.sh    # pad/perf.aura → PAD_PERF_OK + PAD_M7_PERF_OK,
                              # then pad/emacs_test.aura → PAD_PERF_EMACS_OK
bash scripts/smoke_m7.sh      # tests + DIRTY audit + perf → PAD_M7_OK
```

## `aura-pad FILE` (one command): keys unchanged

`aura-pad` is a C launcher that execs aura on `soft/pad/play.aura` with
no bash or stdbuf in between (Soft's `display` already writes each line
on a pipe). It uses the same `play_loop.c` as `pad_play`. In file mode the
loop does one more Soft check per key (`*pf-on*` and the save/quit keys).

```bash
bash scripts/bench_cli.sh     # pp-tip / pp / cli / cli-file, interleaved per round
```

Same harness as wire v2: the 12-row page, cursor at the end of row 6,
dev:v1.0.9, 8 shared cores, six rounds of n=60, rows in a rotating
order. The table shows the median of the six per-run medians, "done" ms
per key.

| key | before: tip `0900d89` `pad_play` | `pad_play` (this tree) | `aura-pad` (play page) | `aura-pad big.txt` (file mode) |
|-----|------|------|------|------|
| insert | 3.29 | 3.23 | 3.28 | 3.34 |
| cursor | 1.89 | 1.87 | 1.85 | 1.90 |

Per-run ranges overlap: insert runs from 3.04 to 3.51 ms across all
rows, cursor from 1.72 to 2.05 ms. That is **no measurable change**; file
mode is at most ~0.05 ms (noise) above the play page.

Startup, from spawn to the first painted frame (`say:`):
- In the container, `pad_play` + script takes ~400 ms. `aura-pad` takes
  ~400 ms on the play page and ~370–435 ms in file mode. Most of that is
  aura loading the Soft files.
- The launcher itself takes ~10 ms (`--where`). Its first probe was
  `aura -e 0` (~95 ms). It now runs `aura --help` (~10 ms) when
  `AURA_PATH` has `std/INDEX.aura`. The full probe runs only when no lib
  dir is found.
- With the docker fallback on the box (native aura needs GLIBC 2.44),
  the first frame takes ~600 ms.

## Wire v2 (`SNAP v2 pad`): no gain, v1 stays the default

The last lever in the ROADMAP latency table is to skip the SNAP rows C
already has. v2 sends only Soft's DIRTY rows plus `GEN`/`base=` and the
body length, and C rebuilds the rest or drops the block (DESIGN §7.1,
`PAD_WIRE2_OK`).

```bash
bash scripts/bench_wire2.sh   # pad-w1 / pad-w2 / pad-tip, interleaved per round
```

Same pty harness as `bench_editors.sh`: the 12-row page, cursor at the
end of row 6, dev:v1.0.9, Soft `c69e644`, 8 cores shared with the
`aura-build-burn` container. Each round runs w1 and w2 in alternating
order, then the tip. Six rounds of n=60 (120 samples per key per run).
The tables show the median of the six per-run medians, "done" ms per key.

| key | before: tip `6b51057` | v1 (`--wire1`) | v2, frame in a Soft call (run 1) | v2, one-row frame inlined (run 2) |
|-----|------------------|----------------|----------------------------------|-----------------------------------|
| insert | 3.15 / 3.27 | 3.23 / 3.24 | **3.52** | **3.16** |
| cursor | 1.74 / 1.79 | 1.78 / 1.71 | **2.26** | **1.86** |

Read each "a / b" cell as run 1 / run 2.

- Run 1: v2 was slower in all six rounds, by +0.3 ms (insert) and
  +0.5 ms (cursor). The frame was built by one more Soft call
  (`pad:w2-frame`). On this tip a loop step with an empty call (two
  Soft calls) costs ~0.26 ms (#4350), which is more than v2 can save.
- Run 2: the one-row frame is inlined at `pad:play-snap` and in the
  play_in fast path. The streams stay byte-identical. The paired per-round
  difference w2 − w1 is +0.14 ms for cursor and −0.13 ms for insert. Per-run
  values overlap (cursor w1 1.63–2.11, w2 1.61–1.96), so this is **no
  measurable gain**.
- What v2 does save: on the big page the wire drops from **44 lines /
  1 044 B per frame to 12 lines / 319 B**, with a median of 1 row sent
  (`wire2_check.py`, 208 frames). Soft writes one `write()` per line
  (`stdbuf -oL`). Under strace the Soft write span per key fell from
  1.2 ms to 0.4 ms, but strace inflates every syscall. Without strace,
  32 fewer small writes are worth ~0.1 ms.
- Where the time goes: Soft compute before the first byte is still
  1.2–1.7 ms per cursor key. A v2 frame string costs ~40 µs more to build
  (two more `number->string`). Terminal bytes are unchanged (81 / 83 B per
  key): C repaints the same rows either way.
- Decision: `pad_play` keeps v1 by default (`--wire1`). v2 stays
  available behind `--wire2` with the full fail-closed smoke, so it can
  become the default when it wins: either when Soft calls get cheap
  (#4350), or when a slow pipe makes wire bytes matter.

## Now: gap2 + Aura-native round (see [`perf-aura.md`](perf-aura.md))

Same pty harness, two runs, ms per key (`out/bench/editors_aura.txt`).
"first" is the first byte, "done" the last byte before 60 ms of quiet.

| key | pad gap round | pad now | pad `PAD_DEFER=1` first / done | vim | emacs -nw |
|-----|---------------|---------|--------------------------------|-----|-----------|
| insert | 4.6 / 4.5 | **4.0 / 4.1** | 3.9 / 4.0 | 0.39 / 0.35 | 0.69 / 0.71 |
| cursor | 1.8 / 1.9 | **1.75 / 1.83** | 1.81 / 1.78 | 0.31 / 0.23 | 0.67 / 0.66 |
| string open | 7.2 / 7.3 | **5.5 / 5.5** | **3.8 / 3.5**, done 5.7 / 5.5 | 0.33 / 0.45 | 1.06 / 0.89 |
| string close | 6.6 / 6.4 | **5.8 / 5.4** | **4.0 / 4.1**, done 6.1 / 5.9 | 0.33 / 0.32 | 0.62 / 0.50 |

- gap2 added two things:
  - a row splice inline in `play-step!`, so a key makes two Soft calls;
  - an O(1) tail memo for string open/close.
- `PAD_DEFER=1` writes an early frame for string open/close: row l is
  exact, and the rows below are as cached. The exact frame follows in
  the same step and is byte for byte the plain stream
  (`PAD_AURA_PERF_OK`). It is jit-lock-defer, not an Aura-only trick.
- Measured negatives:
  - `mutate:rebind` costs 12–18 ms per swap;
  - workspace code runs at file-code speed;
  - CLI fibers are threads that race `read-line` (aura#4356).

  So rebind/relower and fibers give no per-key gain on this tip.
- vim and Emacs are still 3–17× faster.

## Before: end-to-end pty latency (gap round, see [`perf-emacs.md`](perf-emacs.md))

`scripts/bench_editors.sh` covers keystroke → terminal output through a
pty, with the same file and keys for each editor, two runs each, in ms
per key. "before" is tree `94b1fa0`; "after" is `93dfd3c` and `4075523`:

| key | pad before | pad after | vim | emacs -nw |
|-----|-----------|-----------|-----|-----------|
| insert | 7.9 / 8.2 | **4.6 / 4.5** | 0.33 / 0.36 | 0.68 / 0.70 |
| cursor | 6.8 / 7.0 | **1.8 / 1.9** | 0.24 / 0.25 | 0.64 / 0.66 |
| string open | 8.3 / 8.7 | **7.2 / 7.3** | 0.47 / 0.34 | 1.02 / 0.75 |
| string close | 12.3 / 10.1 | **6.6 / 6.4** | 0.41 / 0.40 | 0.55 / 0.60 |

Bytes written to the terminal per key went from a full repaint
(595–1 222 B per frame) to 81 / 83 B. vim and Emacs are still 3–21×
faster. The process, pipes, docker and C cost ~0.45 ms; the rest is
Soft.

What changed:

- One Soft entry per key (`play_in.aura`; C sends one `IN` line per
  `read()`).
- A flat line scanner.
- A C cell-diff tty update with IL/DL.

The remaining insert time: ~2.3 ms in `pad:lc-line!` (named-let entries
and builtins), ~0.8 ms in three closure calls, and ~0.5 ms building the
frame string. A cursor key is one Soft entry plus the frame. Each of
these is Soft call or primitive cost (Aura #4350). Gate:
`PAD_GAP_OK`. Its frames are byte-identical to the old path, and the C
diff screens equal full repaints.

## Before that: Emacs algorithms ported (see [`perf-emacs.md`](perf-emacs.md))

Same Soft binary (`c69e644`), same box. BEFORE is tree `bbc7c04`, AFTER
is this tree. Numbers are µs per key on the twelve-row page from
`soft/pad/perf_probe.aura`, two runs each:

| key | before | after |
|-----|--------|-------|
| insert (type + SNAP) | 32 000–33 600 | **3 570–3 620** |
| cursor left/right | 13 000–14 200 | **1 320–1 350** |
| cursor onto a name used on 5 rows | 34 600–34 700 | **6 900–7 700** |
| enter / join | 32 000–36 500 | **5 400–7 300** |
| command only (gate + apply) | 9 300–9 600 | **620–650** |
| type inside an open string | 217 000–223 000 | **3 400–3 750** |
| open + close a string (avg per key) | 158 000–159 000 | **6 500** (first open 24 000 → **7 000–9 300**, close after it 14 000 → **5 600–7 000**; `perf-emacs.md` rows 7–8) |
| one Soft call (floor) | 270–390 | 260 |

`perf.aura` gates: small page insert / cursor 39 / 18 → **4–5 / 3 ms**;
twelve-row 34 / 21 → **4–5 / 3–4 ms**; cmd-only 7 → **0.6 ms**. Headless
end-to-end `soft_play` stream (200 keys, start page): insert 10.4 →
3.6 ms/key, cursor 16.3 → 3.0 ms/key, with byte-identical SNAP output.

What changed:

- direct commands (`command_loop_1`);
- `try_cursor_movement`;
- `try_window_id` row reuse with shifts;
- jit-lock fontify of the changed line only, in one inline pass that resumes after the unchanged prefix;
- a syntax-ppss start state per line (replaces the whole-page fallback);
- old-row reuse across a string open/close (per-row alt memo, tail memo);
- a region walk below a one-row edit that stops at the first row whose
  start state and carry match (jit-lock-context).

Where an insert's ~3.6 ms goes now: ~4 Soft calls (~1.1 ms), re-lexing
the row tail (~0.5 ms), and ~5 µs primitives for the rest. Gate:
`PAD_PERF_EMACS_OK` needs every fast path equal to its reference or
oracle (43 checks), and insert, cursor, the first string open and the
close after it all < 16 ms.

The sections below are the M6/M7 history, kept for the record.

## Setup

| piece | tip |
|-------|-----|
| aura-pad | this repo tip |
| Soft binary | `/workspace/aura-grok/build/aura` |
| Aura tip | `c69e64453bcdd47f3e8774d82a61139a65d981be` (has #4343 / #4344 / #4345 fixes; earlier rows: `73c012c`) |
| image | `ghcr.io/cybrid-systems/dev:v1.0.9`, `AURA_SANDBOX=off` |
| pages | M6 play page (2 rows, ~34–50 chars); M7 big page (12 × ≤ 40) |

## Numbers

### Two-row play page

| era | insert ms/key | cursor ms/key |
|-----|---------------|---------------|
| M6 tip `78a6b1e` (full re-HL each key) | ~161 | ~288 |
| Soft cache + DIRTY (`648ae08`, re-measured today) | ~41–49 | ~21–29 |
| M7 line cache, Aura `73c012c` | ~23–25 | ~12–14 |
| M7 line cache, Aura `c69e644` | ~33–37 | ~17–22 |
| **Emacs ports, Aura `c69e644`** | **~4–5** | **~3** |

### Twelve-row kid page (M7 fixture)

| path | insert ms/key | cursor ms/key | retok / key |
|------|---------------|---------------|-------------|
| tip `648ae08` (`pad:play-snap`, separate worktree) | ~234 | ~45 | 12 |
| M6 whole-page (`pad:play-snap-m6`, same run as M7) | ~223–234 | ~39–40 | 12 |
| M7 (`pad:play-snap`), Aura `73c012c` | ~23–30 | ~12–13 | 1 |
| M7, Aura `c69e644` | ~33–35 | ~17–19 | 1 |
| **Emacs ports, Aura `c69e644`** | **~4–5** (probe 3.6) | **~3–4** (probe 1.3) | **≤ 1** (tail only) |
| M6 whole-page, Aura `c69e644` | ~284–294 | ~45 | 12 |
| cmd only (gate + apply, no snap) | ~5–7 → 7–9 on `c69e644` → **~0.6** with direct commands | — | — |

Gates: small page insert/cursor < 50 → `PAD_PERF_OK`; twelve-row insert
< 50 **and** ≥ 2× faster than the M6 path → `PAD_M7_PERF_OK`. One
wall-clock retry is allowed and reported (`attempt=2`); two misses fail.
Ideal interactive feel is ≪ 16 ms (60 fps). With the Emacs ports, both
insert and cursor are there (`PAD_PERF_EMACS_OK`). Opening a string above
many rows is under a frame too since the region walk (~7–9 ms, was ~24 ms;
the close after it ~6–7 ms, was ~14 ms), and `emacs_test` gates both.

Versus vi / Emacs: we do **not** claim to be faster. Those editors spend
well under a millisecond of editor time on pages like these. Aura Pad's
Soft key path is now ~1.3–4 ms. Measured with one pty harness on this
box (`scripts/bench_editors.sh`, `perf-emacs.md`): vim 0.2–0.5 ms and
Emacs 0.5–1 ms per key. aura-pad was 7–12 ms end to end and is now
1.8–7 ms after the gap round (top of this page), so they are still
3–21× faster. "Feels faster than vi/Emacs" stays the north star; the
measured Soft floor is below.

## Aura `c69e644`: #4343 closed, but the per-key time did not drop

The Soft rebuild to `c69e644` (#4343 / #4346 closed upstream) did **not**
make keys faster on the file-runner path the pad uses. On the same box
and in the same session, the old binary (`73c012c`) and the new one gave:

| measure | `73c012c` | `c69e644` |
|---------|-----------|-----------|
| small page insert / cursor ms/key | 22–23 / 12 | 33–37 / 17–22 |
| 12-row M7 insert / cursor ms/key | 23–25 / 12 | 33–35 / 17–19 |
| cmd only ms/key | 5–6 | 7–9 |
| `PERF_FLOOR soft_call_us` | 170–233 | 290–429 (typically ~300) |

The #4343 / #4346 repros still grow linearly with the number of defines,
and calls are about 1.5× slower. That is filed as Aura
[#4350](https://github.com/cybrid-systems/aura/issues/4350), with A/B
tables. Other agents share this box, so wall-clock numbers move by
±20%, but the A/B gap showed up in every pair of runs.

### Where one key went on the M7 tree (12-row page, `c69e644`)

`soft/pad/perf_probe.aura` times each piece separately (µs, run inside the
pad stack):

| piece | µs |
|-------|----|
| one empty Soft procedure call (`(lambda () 0)` via a helper) | ~260 |
| `pad:lc-k` (one table lookup) | ~280–300 |
| tokenize ONE 28-char row (`pad:lc-line-toks`) | ~15 000 |
| rebuild ONE row entry (codes → string + toks + tape) | ~26 000 |
| insert command only (gate + apply) | ~9 000 |
| insert key = command + frame + SNAP text | ~33 000 |
| SNAP text when nothing changed | ~5 000 |
| join 12 row strings | ~500 |

So an insert costs about 9 ms for edit, 24 ms to re-tokenize the one
dirty row, and 1 ms for SNAP text. A cursor key costs about 9 ms for
edit and 5 ms for SNAP text. Nothing on that list is big work. One row
is ~50 Soft calls, and each call pays the ~0.26–0.3 ms kernel cost. That
per-call cost is the floor: halving it would halve the key. The cost
lives in the Soft kernel, not in pad code. It is the same cost #4343
targeted, so it is tracked on #4350, not filed again.

## Soft floors (filed upstream)

| limit | evidence | issue |
|-------|----------|-------|
| Per-call Soft cost linear in top-level `#define`s | filler defines + spin | Aura [#4343](https://github.com/cybrid-systems/aura/issues/4343) closed; still linear and ~1.5× slower on `c69e644`: [#4350](https://github.com/cybrid-systems/aura/issues/4350) |
| In-place `vector-set!` / `set-car!` ~15 ms each with the pad loaded | `out/m7/fill_{0,100,300,600}.aura` | [#4346](https://github.com/cybrid-systems/aura/issues/4346) closed; the re-measure still scales (#4350), so the pad keeps `list->vector` |

Pad ships Soft-side wins regardless: line-incremental tokenize, token-
sliced tapes, mark rebuild only on rows that hold the old/new name,
builtin `take`/`drop`/`nth`, never mutate a vector or pair in place
(rebuild with `list->vector` instead). Faster Soft calls would push
insert toward the 16 ms ideal without changing pad edit logic.

## Soft-side wins that landed

1. **M6** — one tokenize per text change (`pad:hl-bundle`); play tape
   cache for cursor moves; single-pass `find-defs`; color via char-list
   → `list->string`; optional SNAP `DIRTY`; C `pad_blit_dirty` paints
   Soft-marked rows.
2. **M7** — per-line cache (`lc.aura`): move / one-line edit / generic /
   full-fallback frames; exact DIRTY (sound + tight, host-audited);
   `pad:take`/`drop`/`nth` on builtins; jump from cache; no
   `vector-set!` / `set-car!` in the key path.
3. **Emacs ports** ([`perf-emacs.md`](perf-emacs.md)): direct commands,
   try_cursor_movement, try_window_id, one-pass inline jit-lock scan with
   prefix resume, syntax-ppss start state per line (no whole-page
   fallback), old-row reuse. ~10× faster keys.

## 中文

按键路径以前每次全量重新高亮（一次按键大约四次 tokenize），小缓冲
区也要 ~0.15–0.3 秒/键。M6 缓存后 ~49/29 ms；M7 行级缓存后小页面
**~23/12 ms**，12 行页面插入 **~230 → ~26–30 ms**、光标 **~13 ms**
（阈值 < 50 ms，且 ≥ 2× 快于 M6 路径 → `PAD_PERF_OK` /
`PAD_M7_PERF_OK`）。光标已低于一帧（16 ms），插入还没有。Soft 全局查
找仍随 define 数量变慢（Aura #4343，约 0.2 ms/次调用）；原地
`vector-set!` 更贵（约 15 ms，#4346），所以 pad 从不原地改向量。
换到 Aura `c69e644`（#4343/#4346 已关闭）后按键**没有变快**：小页面
~33–37/17–22 ms，12 行插入 ~33–35 ms，每次调用 ~0.3 ms（#4350）。
一次插入 ≈ 编辑 9 ms + 重分词一行 24 ms + SNAP 1 ms；地板是 Soft 每
次调用的内核开销。

参考 Emacs 的算法（command_loop_1 直接命令、try_cursor_movement、
try_window_id、jit-lock 只重染改动的行、syntax-ppss 行首状态）移植到
Soft 后（见 perf-emacs.md），12 行页面插入 **~33 → ~3.6 ms**，光标
**~13 → ~1.3 ms**，只跑命令 **~9.5 → ~0.6 ms**，在未闭合字符串里打字
**~220 → ~3.5 ms**。插入和光标都在一帧（16 ms）以内；在多行上方打开字符串
也从 ~24 ms 降到 ~7–9 ms，随后闭合 ~14 → ~6–7 ms（逐行区域遍历，遇到
状态一致的行即停）。剩下的地板是 Soft 每次调用约
0.26 ms（#4350）。我们**不声称比 vi/Emacs 快**。

端到端（pty，gap 轮）：每键一次 Soft 入口、扁平的行扫描器、C 只写变化的
单元格（IL/DL），插入 **~8 → ~4.5 ms**，光标 **~7 → ~1.9 ms**，每键写到终端
的字节从整屏重画 ~600–1200 B 降到 ~81 B。vim 0.3 ms、Emacs 0.7 ms，仍快
3–21×。进程、管道、docker 和 C 只占 ~0.45 ms，其余是 Soft 调用开销（#4350）。

Aura 原生一轮（perf-aura.md）：gap2 把字符串打开从 ~7.2 降到 ~5.5 ms，插入
~4.5 → ~4.0 ms。`PAD_DEFER=1` 先发一帧（当前行准确、下面的行沿用缓存），同一步
里再发准确帧，字符串打开的首字节 ~5.5 → ~3.5–3.8 ms，准确帧与不延迟时逐字节
相同。实测的负面结论：`mutate:rebind` 每次 12–18 ms，workspace 代码与文件代码
同速，CLI 的 fiber 是线程且与 `read-line` 竞争（aura#4356），所以对按键没有加速。
vim/Emacs 仍快 3–17×。

wire v2（只发 Soft DIRTY 行，`GEN`/`base=` + body 长度，C 失败关闭并
请求整帧）：同机交错 A/B，每轮 6 次、n=60。第一次（帧在一次 Soft 调用
里）v2 更慢：光标 2.26 vs 1.78 ms，插入 3.52 vs 3.23 ms。内联单行帧后
第二次：光标 1.86 vs 1.71，插入 3.16 vs 3.24，属于噪声，**没有可测收益**。
线上字节从每帧 44 行 / 1 044 B 降到 12 行 / 319 B，但瓶颈是 Soft 计算
（每键 1.2–1.7 ms）。v1 仍是默认，v2 用 `--wire2` 开启（`PAD_WIRE2_OK`）。

`aura-pad FILE`（一条命令，C 启动器直接 exec aura，不经过脚本）：同机交错
A/B（6 轮、n=60）中，插入 3.28 ms，tip `pad_play` 为 3.29 ms；光标 1.85 vs
1.89 ms。文件模式 3.34 / 1.90 ms，**按键延迟没有变化**。首帧约 0.4 s；
box 上走 docker 后备约 0.6 s。
