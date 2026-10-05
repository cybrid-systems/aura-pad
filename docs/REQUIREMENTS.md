# Aura Pad — requirements

Aura Pad is a **kid-friendly, AI-era editor written in Aura Soft**. It is
not an Emacs or vi clone and not a chat sidebar bolted onto a text box.
It is the smallest editor that shows what only Aura can do: two
worldlines race the same keys, a Soft gate says "no" in words a kid
understands, an AI may **propose** but never silently write, and the
whole editor — buffer, keymap, highlight, jump, marks, kid words — lives
in Soft. C only paints.

Design: [`DESIGN.md`](DESIGN.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md) ·
Latency: [`perf.md`](perf.md) · Engine gaps: [`ISSUES.md`](ISSUES.md).

## 1. Who

| who | what they need from the pad |
|-----|-----------------------------|
| **Kid writer** (8–12, first keyboard, first `(define …)`) | type a story or a tiny program; never get scolded; see *why* something was refused in ≤ 8 plain words; undo anything |
| **Grown-up helper** (parent / teacher) | trust that nothing happens behind the kid's back: every AI change is a visible card that was gated, raced and kept on a better score, and can be taken back |
| **Aura author / engine developer** | a real Soft client that exercises `hot-strategy`, fibers, `query:*` / `mutate:*`, snapshot/restore — and files honest engine bugs "Filed from: aura-pad" instead of hiding them behind wrappers |
| **AI proposer** (MiniMax via host script, later others) | a narrow, typed slot (a pack / helper / macro lambda) and a score it can try to beat; nothing else |

## 2. Jobs to be done

1. **"Let me write."** Type, move, delete, new line, undo, kill/yank,
   mark region — on a page of up to 12 × 40, with highlight and def/use
   marks, and keys that feel immediate.
2. **"Tell me why not."** Every refused key or command changes nothing
   and says one short kind sentence (`there is no line there`, `this line
   is full`, `put the cursor on a name first`).
3. **"Where does this come from?"** Jump to where a name is born
   (ctrl-g), count where it is used (ctrl-r), jump back (ctrl-b).
4. **"Help me, but ask first."** An AI proposes a keymap pack, a command
   helper or a macro; Soft gates it, races it against the current one on
   the same keys/goal, KEEPs only a strictly better score, otherwise
   heals and DROPs. The kid can undo a KEEP and the score is re-checked.
5. **"Two ideas, same keys."** Gentle vs bold keymaps, two buffer laws,
   two helpers: run as two worldlines; the better one is stamped, the
   other leaves no trace.
6. **(Aura author)** "Show me the engine is honest": every pad feature
   names the tip surface it uses, prints `GAPS …` for unbound names, and
   points at the Aura issue.

## 3. Non-goals

- Not an Emacs/vi/VS Code replacement: no plugin system, no modal
  editing language, no LSP server, no file manager, no huge files.
- No ghost-text autopilot: the AI never types into the page directly.
- No C-side editor logic: C never tokenizes, gates, edits, maps a key or
  chooses a kid word (enforced by `PAD_C_THIN_OK`).
- No fake engine APIs: an unbound tip name is a `GAPS` line + an Aura
  issue, never a Soft shim pretending to be the engine.
- No network or shell from Soft: AI calls go through a host script.
- No GUI toolkit (SDL/X11) until the ANSI path is proven; no Unicode
  input beyond what Soft strings already carry.

## 4. Aura-unique musts

| must | meaning in the pad | where |
|------|--------------------|-------|
| **Worldlines KEEP / DROP** | two strategies on the same keys/goal; strictly higher score is stamped (KEEP), the other leaves no trace (DROP). Tie is DROP (M0 gentle-tie is the only legacy exception). | M0 `rules.aura`, M3 `helper.aura`, M4 `macro.aura` |
| **Honest fibers** | `WORLD line=fiber_live` only when every join returns a score, `joins == spawned`, `backend > 0`; else `host-sequential` | M0+ |
| **Soft gate** | every command / proposal is checked before apply; REJECT never mutates and never pushes undo; kid reason + `say="…"` | `buffer`, `lines`, `edit`, `hot`, `m4` |
| **Propose** | AI fills a hot slot (`std/hot-strategy` `pd:law` / `pd:helper` / `pd:macro`); gate → probe → race → KEEP or `heal!` + DROP; undo KEEP re-scores and fails loud on mismatch | M1–M4 |
| **query / mutate** | use only tip-bound `query:*` / `mutate:*` (`(query :find)`, `:def-use`, `query:defines`, `mutate:summary`, `mutate:rebind`, …); unbound names are `GAPS` | M5 `query.aura` |
| **FlatAST-friendly model** | buffer is lists of char codes / lines; pure step functions (fiber-safe); M9 moves the source of truth into the Aura workspace | M0–M9 |
| **Soft owns logic, C blits** | Soft packs a `SNAP v1 pad` block (text, HL letters, marks, cursor, kid words, DIRTY rows); C checks shape (fail closed) and paints; `pad_play` forwards raw bytes | M6–M7 |

## 5. Success metrics

### Correctness (gated in CI-style smoke)
- `PAD_LIVE=0 bash scripts/smoke.sh` → `PAD_SMOKE_OK` (M0–M8) on the
  pinned image + tip binary.
- Host models byte-match Soft (`PAD_*_MODEL_OK`); C goldens + fail-closed
  fixtures; `PAD_C_THIN_OK`.
- M7: every cached key frame equals the whole-page oracle byte for byte
  (`PAD_M7_TEST_OK`); DIRTY is sound and tight (`PAD_M7_DIRTY_OK`).

### Kid experience
- 100% of REJECTs carry a kid sentence (≤ 8 words, no jargon).
- 0 AI changes reach the page without a visible gate + race + KEEP.
- Every KEEP is undoable; undo re-scores (mismatch fails loud).

### Key latency — honest numbers
Measured by `scripts/smoke_perf.sh` (Soft only: gate + apply + SNAP
pack, no terminal). Tip binary `73c012c`, image `dev:v1.0.9`.

| page | path | insert ms/key | cursor ms/key |
|------|------|---------------|---------------|
| 2 rows (M6 play page) | M6 tip `648ae08` | ~41–49 | ~21–29 |
| 2 rows | **M7** | **~23** | **~12** |
| 12 rows × ≤ 40 | M6 tip `648ae08` | ~234 | ~45 |
| 12 rows × ≤ 40 | **M7** | **~26–30** | **~13** |

Targets and gates:

| metric | gate today | target |
|--------|-----------|--------|
| cursor key, kid page | < 50 ms (`PAD_PERF_OK`) | < 16 ms (one 60 fps frame) — **met (~13 ms)** |
| insert key, kid page | < 50 ms (`PAD_PERF_OK`, `PAD_M7_PERF_OK`) | < 16 ms — **not met (~23–30 ms)** |
| key cost vs page size | M7 insert ≥ 2× faster than M6 on 12 rows | O(edited line), not O(page) — **met** |

**Versus vi / Emacs (honesty rule).** vi and Emacs process a key in
well under a few milliseconds of editor time on files like these; most of
their end-to-end latency is the terminal and display. Aura Pad's Soft
key path is still **~10× slower than that** for inserts. We do **not**
claim to be faster than vi/Emacs. "Feels faster than vi/Emacs" stays the
north star; the measured floor is the Soft interpreter: ~0.2 ms per Soft
call with the pad loaded (Aura #4343) and ~15 ms per in-place
`vector-set!` / `set-car!` (new finding, see `perf.md`). The pad keeps
doing every Soft-side win it can and publishes the numbers either way.

## 6. Constraints

- Soft binary `/workspace/aura-grok/build/aura` (tip `73c012c`), image
  `ghcr.io/cybrid-systems/dev:v1.0.9`, `AURA_SANDBOX=off`. Never
  `build_soft4132`.
- Soft reserved: never bind `quote`. Keep pad state pure where fibers
  touch it.
- C: C11, `-Wall -Wextra -pedantic -Werror`, no dependencies.

## 中文摘要

**是什么**：给小朋友用的、AI 时代的 Aura 原生 Soft 编辑器——不是
Emacs/vi 克隆，也不是聊天侧栏。缓冲区、按键表、高亮、跳转、标记、给
孩子看的话全部在 Soft；C 只负责画。

**给谁**：小作者（8–12 岁）、陪伴的大人、Aura 引擎开发者、AI 提议者。

**要做的事**：能写；被拒绝时用一句短短的好话说明原因且什么都不改；能
找到名字在哪里出生/被用到；AI 只能**提议**，Soft 门卫把关、同键赛跑、
严格更高分才 KEEP，否则自愈 DROP，KEEP 可撤销并重新打分；两条世界线
跑同一串键，赢的盖章，输的不留痕。

**不做**：编辑器大全、幽灵补全、C 侧编辑逻辑、假装引擎 API、Soft 里
联网。

**Aura 独有的必须项**：世界线 KEEP/DROP、诚实 fiber、Soft 门卫、
Propose（hot-strategy 槽）、只用 tip 上真实的 query/mutate（没有就写
GAPS 并提 issue）、Soft 管逻辑 C 只 blit。

**指标**：全部冒烟通过；每个拒绝都有孩子能懂的话；AI 改动必经门卫+
赛跑+KEEP。按键延迟如实公布：M7 后小页面插入 ~23 ms、光标 ~12 ms；
12 行页面插入 ~230 → ~26–30 ms。光标已低于一帧（16 ms），插入还没有。
**我们不声称比 vi/Emacs 快**——它们编辑器侧每键远低于几毫秒；Aura Pad
的下限是 Soft 解释器（#4343 每次调用 ~0.2 ms，以及原地 `vector-set!`
~15 ms 的新发现）。
