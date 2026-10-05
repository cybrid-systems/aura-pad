# Aura Pad key latency

Kid pad keys should feel snappier than a sleepy editor — Soft owns the
editor, so the interactive path is Soft gate + apply + SNAP pack (+ thin
C blit). This page publishes measured **ms/key** for the scripted Soft
stream on tip Soft. See [`REQUIREMENTS.md`](REQUIREMENTS.md) §5 and
[`DESIGN.md`](DESIGN.md) §8 for the budget and the honesty rule.

```bash
bash scripts/smoke_perf.sh    # Soft pad/perf.aura → PAD_PERF_OK + PAD_M7_PERF_OK
bash scripts/smoke_m7.sh      # tests + DIRTY audit + perf → PAD_M7_OK
```

## Setup

| piece | tip |
|-------|-----|
| aura-pad | this repo tip |
| Soft binary | `/workspace/aura-grok/build/aura` |
| Aura tip | `73c012c95d4ca0d203950e60d9662224f738caa0` |
| image | `ghcr.io/cybrid-systems/dev:v1.0.9`, `AURA_SANDBOX=off` |
| pages | M6 play page (2 rows, ~34–50 chars); M7 big page (12 × ≤ 40) |

## Numbers

### Two-row play page

| era | insert ms/key | cursor ms/key |
|-----|---------------|---------------|
| M6 tip `78a6b1e` (full re-HL each key) | ~161 | ~288 |
| Soft cache + DIRTY (`648ae08`, re-measured today) | ~41–49 | ~21–29 |
| **M7 line cache** | **~23–25** | **~12–14** |

### Twelve-row kid page (M7 fixture)

| path | insert ms/key | cursor ms/key | retok / key |
|------|---------------|---------------|-------------|
| tip `648ae08` (`pad:play-snap`, separate worktree) | ~234 | ~45 | 12 |
| M6 whole-page (`pad:play-snap-m6`, same run as M7) | ~223–234 | ~39–40 | 12 |
| **M7** (`pad:play-snap`) | **~25–30** | **~13** | **1** |
| cmd only (gate + apply, no snap) | ~5–7 | — | — |

Gates: small page insert/cursor < 50 → `PAD_PERF_OK`; twelve-row insert
< 50 **and** ≥ 2× faster than the M6 path → `PAD_M7_PERF_OK`. One
wall-clock retry is allowed and reported (`attempt=2`); two misses fail.
Ideal interactive feel is ≪ 16 ms (60 fps): **cursor is there, insert is
not**.

Versus vi / Emacs: we do **not** claim to be faster. Those editors spend
well under a few milliseconds of editor time on pages like these; Aura
Pad's Soft key path is still ~10× that for inserts. "Feels faster than
vi/Emacs" stays the north star; the measured Soft floor is below.

## Soft floors (filed upstream)

| limit | evidence | issue |
|-------|----------|-------|
| Per-call Soft cost linear in top-level `#define`s | filler defines + spin | Aura [#4343](https://github.com/cybrid-systems/aura/issues/4343) (~0.2 ms/call with the pad loaded) |
| In-place `vector-set!` / `set-car!` ~15 ms each with the pad loaded (slope ~6× steeper than calls) | `out/m7/fill_{0,100,300,600}.aura` | **new** — drafted, to be filed from aura-pad (see [`ISSUES.md`](ISSUES.md)) |

Pad ships Soft-side wins regardless: line-incremental tokenize, token-
sliced tapes, mark rebuild only on rows that hold the old/new name,
builtin `take`/`drop`/`nth`, never mutate a vector or pair in place
(rebuild with `list->vector` instead). Faster Soft lookup would push
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

## 中文

按键路径以前每次全量重新高亮（一次按键大约四次 tokenize），小缓冲
区也要 ~0.15–0.3 秒/键。M6 缓存后 ~49/29 ms；M7 行级缓存后小页面
**~23/12 ms**，12 行页面插入 **~230 → ~26–30 ms**、光标 **~13 ms**
（阈值 < 50 ms，且 ≥ 2× 快于 M6 路径 → `PAD_PERF_OK` /
`PAD_M7_PERF_OK`）。光标已低于一帧（16 ms），插入还没有。Soft 全局查
找仍随 define 数量变慢（Aura #4343，约 0.2 ms/次调用）；原地
`vector-set!` 更贵（约 15 ms，已整理新 issue），所以 pad 从不原地改
向量。我们**不声称比 vi/Emacs 快**。
