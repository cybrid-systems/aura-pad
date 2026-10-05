# Aura Pad key latency (Soft hot path)

Kid pad keys should feel snappier than a sleepy vi/Emacs — Soft owns the
editor, so the interactive path is Soft tokenize + SNAP pack + thin C
blit. This page publishes measured **ms/key** for the scripted
`pad_play` stream on tip Soft.

```bash
bash scripts/smoke_perf.sh    # Soft pad/perf.aura → PAD_PERF_OK
```

## Setup

| piece | tip |
|-------|-----|
| aura-pad | this repo tip |
| Soft binary | `/workspace/aura-grok/build/aura` |
| Aura tip | `73c012c95d4ca0d203950e60d9662224f738caa0` |
| image | `ghcr.io/cybrid-systems/dev:v1.0.9`, `AURA_SANDBOX=off` |
| buffer | `*play-start*` ≈ 34–50 chars (two lines) |

## Before (M6 tip `78a6b1e`, full re-HL each key)

Every `pad:play-emit!` called `pad:snap-text` → `pad:hl-color` (full
scan) + `pad:v-marks` (which re-tokenized again via `sym-at` /
`find-defs` / `find-refs`). One key ≈ **four** full tokenizes.

| path | ms/key (n=20) |
|------|----------------|
| insert + snap | **~161** |
| cursor left/right + snap | **~288** |
| `pad:hl-color` alone | ~57–83 |
| `pad:v-marks` alone | ~227 |

That is why typing felt ~0.15s/key.

## After (Soft cache + one-tokenize SNAP)

Soft-side wins (C still has **zero edit logic**):

1. **One tokenize per text change** — `pad:hl-bundle` builds the color
   tape and feeds the same toks into marks / jump helpers.
2. **Play cache** (`keys.aura`) — cursor-only moves reuse `*pl-tape*` /
   `*pl-toks*`; marks rebuild only when the name under point changes.
3. **Single-pass `find-defs`** — no O(n²) `length` + `pad:hl-nth` walks.
4. **Color via char-list → `list->string`** — no per-char `string-append`.
5. **Optional `DIRTY lines=`** in SNAP — C `pad_blit_dirty` paints only
   Soft-marked rows (interactive ANSI); plain/golden full blits unchanged.

| path | ms/key (n=20) | vs before |
|------|----------------|-----------|
| insert + snap | **~36** | ~4.5× |
| cursor left/right + snap | **~18** | ~16× |

Threshold gated by `smoke_perf.sh`: **median < 50 ms/key** for both
paths on the small play buffer → `PAD_PERF_OK`. Ideal interactive feel
is ≪ 16 ms (60 fps); Soft tip still pays a **per-call cost that grows
with top-level define count** (Aura [#4343](https://github.com/cybrid-systems/aura/issues/4343)),
so a single full tokenize of a tiny buffer is still tens of ms.

## Soft kernel limits (filed upstream)

| limit | evidence | Aura issue |
|-------|----------|------------|
| Global / procedure lookup scales with `#define`s | filler-define spin probe | [#4343](https://github.com/cybrid-systems/aura/issues/4343) |
| One Soft tokenize of ~50 chars ≈ 30–40 ms after pad loads | `out/probe/key_*.txt` | update on #4343 + key-latency note |

Pad ships the Soft-side wins above regardless; faster Soft lookup would
push insert toward the 16 ms ideal without changing pad edit logic.

## 中文

按键路径以前每次都全量重新高亮（一次按键大约四次 tokenize），小缓冲
区也要 **~0.15–0.3 秒/键**。现在 Soft 侧：文本变了才 tokenize 一次；
光标移动复用色带；`find-defs` 单次走过；SNAP 可带 `DIRTY` 让 C 少画几
行。测得插入 **~36 ms/键**、光标 **~18 ms/键**（阈值 < 50 ms →
`PAD_PERF_OK`）。Soft 全局查找仍随 define 数量变慢（Aura #4343），
那是内核限制，pad 已把 Soft 侧能做的先做完。
