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

## Now: Emacs algorithms ported (see [`perf-emacs.md`](perf-emacs.md))

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
| open + close a string (avg per key) | 158 000–159 000 | **13 700–13 900** (first open ~24 000) |
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
- old-row reuse across a string open/close.

Where an insert's ~3.6 ms goes now: ~4 Soft calls (~1.1 ms), re-lexing
the row tail (~0.5 ms), and ~5 µs primitives for the rest. Gate:
`PAD_PERF_EMACS_OK` needs every fast path equal to its reference or
oracle (30 checks), and insert and cursor < 16 ms.

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
many rows is the one key still over a frame (~24 ms).

Versus vi / Emacs: we do **not** claim to be faster. Those editors spend
well under a millisecond of editor time on pages like these. Aura Pad's
Soft key path is now ~1.3–4 ms. We have not measured vi/Emacs with the
same harness. "Feels faster than vi/Emacs" stays the north star; the
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
**~220 → ~3.5 ms**。插入和光标都在一帧（16 ms）以内；唯一还超过一帧的
是在多行上方打开字符串（~24 ms）。剩下的地板是 Soft 每次调用约
0.26 ms（#4350）。我们**不声称比 vi/Emacs 快**。
