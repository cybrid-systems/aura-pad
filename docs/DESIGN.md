# Aura Pad — design

Requirements: [`REQUIREMENTS.md`](REQUIREMENTS.md). Roadmap:
[`ROADMAP.md`](ROADMAP.md). Milestone detail: [`m0.md`](m0.md) …
[`m6.md`](m6.md), [`m7.md`](m7.md). Latency: [`perf.md`](perf.md),
[`perf-emacs.md`](perf-emacs.md).
Engine gaps: [`ISSUES.md`](ISSUES.md). Later notes: [`NEXT.md`](NEXT.md).

## 1. One rule

**Soft owns every decision. C owns pixels.** If C would need to know what
a key, a word or a character *means*, that logic goes in Soft. C may
parse the wire shape, map a letter to a color, and forward bytes —
nothing else (`PAD_C_THIN_OK` greps the C sources for editor words, HL
keywords, kid words and key-byte comparisons).

## 2. Layers

```
                 host (python3, no Soft HTTP)
   propose_minimax.py -- lambda text --+      *_model.py -- byte-for-byte oracles
                                       v
 [ Aura Soft (tip binary) ]
   world     rules.aura  race-thunks!, WORLD line, KEEP/DROP stamp       (M0)
             hot.aura    std/hot-strategy slots + gate words              (M1/M2)
             pack.aura / helper.aura / macro.aura  Propose → gate →       (M1–M4)
                         probe → race → KEEP | heal!+DROP, undo re-score
   model     buffer.aura chars, gate, sim                                 (M0)
             lines.aura  (line col), line ops, pure lsim                  (M3)
             edit.aura   undo/kill/mark/indent, egate/eapply, goal3       (M3.5)
             m4.aura     story/scratch pads, find/replace, rec/play, law  (M4)
   analysis  hl.aura     tokenizer + HL tape  P K S T C Q M N .           (M5)
             jump.aura   goto-def / find-refs / jump-back (token based)   (M5)
             query.aura  tip query:* / mutate:* bridge, USED/GAPS lists   (M5)
             std.aura    std/query + std/mutate requires, loaded first    (M9)
             ws.aura     workspace notebook: check = set-code+eval-current (M9)
             pen.aura    helper/macro/law rebind: REJECT/KEEP/DROP + heal  (M9)
   view      view.aura   SNAP v1 pad packer (whole page)                  (M6)
             lc.aura     line cache: per-line toks/tape/marks, DIRTY      (M7)
             keys.aura   keymap bytes→commands, play gate, play state     (M6/M7)
             play.aura   loop: IN/KEY lines in, SNAP blocks out           (M6)
                                       |
                                       | SNAP v1 pad … END (stdout / file)
                                       v
 [ C (thin viewport, no logic) ]
   snap.c  reader: fail closed, last complete block wins; ANSI/plain blit;
           pad_blit_dirty repaints DIRTY rows + any row whose text differs
   pad_view.c  blit one snapshot (file / stream)
   pad_play.c  raw terminal, forwards every byte as "IN <n>", blits Soft frames
```

All model step functions are pure on their state lists (fiber-safe); only
`pad:play-*` and `pad:lc-*` write module globals, and only with `set!`
(never in-place `vector-set!` / `set-car!` — see §8).

## 3. Editor model

- **Buffer.** M0: one list of char codes. M3+: list of lines, each a list
  of char codes; point `(line col)`, 0-based, `col` may equal line length.
  Page limits are Soft globals (`*max-col*`, `*max-lines*`; play page
  40 × 12).
- **Edit state** (M3.5) `(L line col kill mark undo)`; undo is an 8-deep
  stack of `(L line col)` snapshots; a text command pushes one snapshot
  and clears the mark; a REJECT never pushes.
- **Commands** are words (`left` `right` `home` `end` `next-line`
  `prev-line` `back` `open-line` `kill-line` `yank` `undo` `indent`
  `dedent` `bob` `eob` `set-mark` `kill-region` `copy-region`, M4 `find:`
  `find-next` `replace:` `replace-all:` `switch:` `rec` `stop` `play`) or
  a char code. Each goes `gate → apply`. Gate returns `"ok"` or a kid
  reason; `pad:kid-say` / `pad:play-say` turn reasons into sentences.
- **Highlight** (M5): one tokenizer, token `(kind start end text)`, kinds
  `P` paren, `K` keyword, `S` symbol, `T` string, `C` comment, `Q`
  `query:*`, `M` `mutate:*`, `N` number. The HL tape is one letter per
  char.
- **Jump** (M5): token based. A def is `(define NAME` or `(define (NAME`;
  a ref is any S/K/Q/M token with the same text. Jump state
  `(src point stack)`; reasons `no-symbol` `no-def` `no-ref`
  `nothing-to-back`. Engine goto-def waits on Aura #4344.
- **Macro** (M4): `rec`/`stop`/`play`; `play` re-gates every step and
  counts refusals.
- **Multi-buffer** (M4): named pads `story` / `scratch`, `switch:NAME`,
  kill text travels. M11 adds an `aura` notebook pad.

## 4. Worldlines and the gate (M0–M4)

1. Build an isomorphic start for each strategy (keymap pack, buffer law,
   command helper, macro).
2. Race both on the **same** seeded keys / goal — on fibers when the tip
   gives real joins.
3. The Soft gate rejects bad steps before apply (`REJECT mid=.. reason=..
   say="…"`).
4. Score `edits_ok - 2*rejects - distance_from_goal` (+ per-milestone
   hooks; M3.5 three-line goal; M4 story goal).
5. KEEP the strictly higher score and stamp it into main; DROP the loser
   (no stamp). Tie is DROP except the M0 gentle-tie legacy rule.
6. `WORLD line=fiber_live backend=.. joins=n/n` only when every join
   returns a number and `backend > 0`; otherwise `host-sequential`.

Keymaps (M0): `map-gentle` (mid 1, Δ±1, reject `too-far`, max len 8) vs
`map-bold` (mid 2, Δ±3 clamped, max len 20).

## 5. AI Propose flow (M2–M4, M8 next)

```
host propose_minimax.py ── "(lambda () …)" ──> Soft
  clean → gate (shape, length, banned words: set! vector-set! display write
          mutate eval load shell http read-file set-code fiber: hot-strategy
          pd:* pad:live …; M4 adds kind-word list)
        → hot-strategy:swap! into slot (pd:law | pd:helper | pd:macro)
        → probe (call the slot; bad shape → heal! + HEAL line)
        → race trial vs shadow (current main) on the same keys/goal
        → trial > base ? KEEP (stamp, new main, history) : heal! + DROP
  undo KEEP: restore previous main, re-play, re-score; mismatch fails loud
```

Soft never speaks HTTP; the key lives in `~/.config/aura-build/
minimax.env` and is never printed. Fixtures (`bad`, `noisy`, `ugly`,
`worse`, `tie`, `better`) keep the flow testable offline; live runs sit
behind `PAD_LIVE`.

## 6. Soft query / mutate (M5)

Only tip-bound surfaces: `query:list-categories`, `query:help`,
`(query :find)`, `(query :def-use)`, `query:defines`,
`query:find-by-name`, `mutate:summary`, `mutate:boundary-safe?`,
`mutate:boundary-depth`, `mutate:rebind`, `ast:snapshot` /
`ast:restore`. `set-code` + `eval-current` load a notebook. Since Soft
tip `c69e644` (#4344 / #4345 closed) `define-lookup`, `query:code`,
`query:ref-counts` and `query:node-types` are bound too. `pad:q-probe`
calls each one in a `try` at load, so a smoke prints
`USED define-lookup.query:code.query:ref-counts.query:node-types` and
`GAPS none`. Any name that comes back unbound still goes on `GAPS` and
gets filed, never wrapped. Jump takes engine define points only when they
land on the name. `define-lookup` line/col are 0 today (#4347), so jump
stays on Soft HL. Entry files load `std.aura` (the std/query + std/mutate
requires) before any other pad file (#4351). Because per-call cost
scales with defines (#4343, still linear on tip: #4350), the pad never
`set-code`s per keystroke: one load per notebook check (M9, `ws.aura`).

## 7. SNAP protocol (`SNAP v1 pad`, opt-in `SNAP v2 pad`)

Same `SNAP v1 … END` family as aura-parkour / aura-tetris.

```
SNAP v1 pad
TITLE aura pad (Soft) keys=11 no=1
CURSOR line=1 col=1
SAY jumped to where hello is born
LEGEND K=magic-word S=name T=quote C=note N=number P=paren Q=ask M=change d=born-here r=used-here
DIRTY lines=0,1            # optional (M6 perf, exact from M7)
ROWS n=2
T (define (hello x) (+ x 1))
H PKKKKKK.PSSSSS.SP.PS.S.NPP
M .........ddddd............
T (hello 4)
H PSSSSS.NP
M .rrrrr...
END
```

- `T` text, `H` HL slice, `M` mark slice; `|T| = |H| = |M|`. HL letters
  `P K S T C Q M N .`; mark letters `d` (born here), `r` (used here), `.`.
- `CURSOR` 0-based; `col` may equal row length.
- `DIRTY lines=` (M7 semantics): sorted 0-based rows whose `T`/`H`/`M`
  changed since the previous block **plus the cursor row**; omitted on the
  first block of a session (C full-blits). It is a hint: C still compares
  rows and repaints the previous cursor row. `scripts/dirty_check.py`
  audits soundness (no changed row missing) and tightness (no unchanged
  row other than the cursor row).
- Fail closed: bad line, wrong lengths, unknown letter, cursor out of
  range or missing `END` drops the whole block; a stream keeps the last
  complete block.
- Input side (`pad_play` → Soft): `IN <byte>` per raw key byte,
  `KEY <word>` scripted, `QUIT`. Escape sequences are decoded in Soft
  (`pad:key-step`).

### 7.1 Wire v2 (`SNAP v2 pad`, opt-in)

v1 resends every row on every frame (12-row page: 44 lines, ~1 KB per
key). v2 carries only the rows Soft already marked DIRTY:

```
SNAP v2 pad
GEN 7 base=6               # rows not sent = rows of frame 6; base=- : full
TITLE aura pad (Soft) keys=11 no=1
CURSOR line=1 col=1
SAY jumped to where hello is born
LEGEND K=magic-word ...
ROWS n=2 body=123          # body = bytes of the whole v1 ROWS body
R 1                        # once per sent row (Soft's DIRTY set)
T (hello 4)
H PSSSSS.NP
M .rrrrr...
END
```

- Soft decides: the rows sent are the exact M7 DIRTY rows
  (`soft/pad/wire2.aura`, `pad:w2-frame`). After an early frame
  (`PAD_DEFER`) Soft also resends row l in the next frame, because C
  holds the early row l.
- C (`c/snap.c`) only rebuilds. A delta is accepted only if `base` is the
  generation of the frame C holds, every unsent row exists there, no `R`
  is repeated or out of range, `body=` matches the rebuilt rows and the
  cursor is in range. A full frame must send every row. Anything else
  drops the whole block, and C keeps the last good frame. C never picks
  or guesses a row.
- Recovery: after a dropped v2 block `pad_play` writes `WIRE 2 FULL` once.
  Soft answers with a full frame, and every later delta is based on it.
  A bad full frame earns at most 3 asks in a row. `pad_view` (file
  replay) has no channel back, so it only drops.
- Handshake: `pad_play --wire2` writes `WIRE 2` to Soft first, and Soft
  answers with a full v2 frame. `WIRE 1` switches Soft back to v1.
  Without the offer, Soft writes v1 only, which is the default
  (`--wire1`). See `perf.md` "wire v2" for why.
- Oracle: `scripts/wire2_check.py` rebuilds v2 frames independently and
  requires them to equal the v1 frames for the same keys, one for one.
  It also requires the C `--replay-full` bytes to match per frame and
  runs `term_model.py` on the v2 cell diff (`smoke_wire2.sh` →
  `PAD_WIRE2_OK`).

## 8. Key path and performance budget (M6 → M7 → Emacs ports)

Per key: `play-line!` (decode) → `play-cmd!` (gate + apply) →
`play-snap` → `display`. Budget on kid pages (≤ 12 × 40):

| stage | M6 tip | M7 | Emacs ports | note |
|-------|--------|----|-------------|------|
| gate + apply (insert) | ~12 ms | ~6–9 ms | ~0.6 ms | direct commands `pad:play-cmd!` |
| re-tokenize | whole page (~1 ms/char) | edited line only (~15 ms) | tail of the edited line, one inline pass (~3 ms full row) | `pad:lc-scan` |
| HL tape | per char | per token slice | run-string slices in the scan | |
| marks | whole page per name change | rows holding old/new name | same, inline | carry key per row |
| SNAP rows | rebuilt | cached row strings | + cached body; kept rows reuse their string | `*lc-body*` |
| string left open | whole page | whole-page fallback | per-line start state (syntax-ppss) | `ins` field |
| **insert total, 12 rows** | **~230 ms** | **~26–35 ms** | **~3.6 ms** | `PAD_PERF_EMACS_OK` |
| **cursor total, 12 rows** | ~40 ms | **~13–19 ms** | **~1.3 ms** | |

The Emacs mapping (file/function → Soft function → µs) is in
[`perf-emacs.md`](perf-emacs.md).

**Line cache (M7, `lc.aura`).** Per line an entry `(codes str toks tape
open last1 last2 syms rtoks ins)` and a record `(entry mkey mrow p1 p2)`.
`ins` is the line's start state (it starts inside a string). Frames:

- *move* (same lines object): name under cursor unchanged → only the
  cursor row is dirty; changed → rebuild mark rows only where the old or
  new name occurs (`member` on the row's symbol list; carry `p1 p2` kept
  per row).
- *one-line edit* (rows differ only at the cursor row; checked with
  builtin `drop`/`reverse`/`equal?`): re-scan that row from the end of
  its unchanged prefix. If the name, the def-carry and the end state of
  the row are all unchanged, no other row can change.
- *generic* (enter, join, yank, undo, region kill, end-state flip): match
  each new row to an old row by codes **and** start state, at shift
  `d, 0, -1, +1`, then against the rows saved before the last string flip.
  Reuse entries and row strings; rebuild marks with carry.
- A string that runs off a line unclosed (the only token that can cross a
  newline) no longer forces a whole-page tokenize. The rows below are
  re-scanned with the new start state (like Emacs `jit-lock-contextually`,
  but at once instead of after idle time). `full_frames` counts these
  generic frames.

**Soft floor.** With the pad loaded a Soft call costs ~0.25–0.3 ms on
`c69e644` (Aura #4343 → #4350: linear in top-level defines; primitives
slow down too) and an in-place `vector-set!` /
`set-car!` ~15 ms (slope ~6× steeper than calls; drafted to file from
aura-pad, see `ISSUES.md` / `perf.md`). So the pad avoids per-char Soft
loops where a builtin can do it, never mutates a vector or pair in place,
and keeps per-key Soft calls to O(edited line + rows touched).

## 9. Observability

- Soft log lines: `REJECT … say="…"`, `SCORE`, `RACE base= trial=`,
  `KEEP`/`DROP`, `HEAL`, `WORLD line=…`, `GAPS …`, `QUERY …`, `MUTATE …`.
- M7 counters `pad:lc-stats`: `frames moves line_edits retok_lines
  full_frames` (printed as `M7STATS` in tests); perf lines `PERF`,
  `PERF_BIG` (M6 vs M7 ms/key, cmd-only ms, `retok_lines_per_key`),
  `PERF_FLOOR soft_call_us`.
- C: `pad_view --stats` → `PAD_C_BLIT rows= cells= cursor= marks= snaps=
  rejected= mode=`; `pad_play --stats` → `PAD_C_PLAY keys= snaps=
  rejected= cursor=`.
- Host audits: `*_model.py` byte oracles, `dirty_check.py`
  (`M7_DIRTY blocks= pairs= partial=`).
- Every smoke marker is greppable: `PAD_M0_OK` … `PAD_M9_OK`,
  `PAD_SMOKE_OK`.

## 10. Honesty rules (all milestones)

1. A REJECT never mutates and never pushes undo (also inside `play`).
2. KEEP only on a strictly better score; undo restores a recorded
   snapshot and re-scores; a mismatch fails loud.
3. `fiber_live` only when every join lands.
4. Unbound tip names are `GAPS` + an Aura issue "Filed from: aura-pad";
   no fake wrappers. Until `mutate:atomic-batch` exists, a failed probe is
   `ast:snapshot` / `ast:restore` / `heal!` — never called a transaction.
5. A macro body or proposal with a banned or unkind word never reaches a
   slot.
6. C never decides anything (`PAD_C_THIN_OK`).
7. Performance claims are measured by a checked-in smoke on the pinned
   image and published with the "before" number; no claim of beating
   vi/Emacs until a measurement says so.
8. A cache must equal its oracle: every M7 frame is diffed against the
   whole-page `pad:snap-text` in `m7_test.aura`.
9. Soft reserved: never bind `quote`.

## 11. Roadmap

| milestone | status | one line |
|-----------|--------|----------|
| M0 | done | dual keymap race, Soft gate, KEEP/DROP, honest worldline |
| M1 | done | `hot-strategy` keymap pack swap / heal mid-run |
| M2 | done | MiniMax proposes a pack; gate + race + KEEP only if better |
| M3 | done | multi-line buffer + command-helper Propose |
| M3.5 | done | undo/yank/indent/mark/region, three-line goal, undo KEEP |
| M4 | done | story/scratch pads, find/replace, macros, law race, macro Propose |
| M5 | done | Soft HL, LSP-lite jump/refs, honest query/mutate bridge |
| M6 | done | thin C viewport, SNAP v1 pad, Soft keymap/play; key-latency cache |
| **M7** | **done** | **snappy pad: line-incremental Soft key path, exact DIRTY** |
| **M8** | **done** | **kid onboarding card + intent worldline (goal race, story cards)** |
| **M9** | **done** | **workspace notebook: load once per check, pen at mutation boundaries** |
| **M10** | **done** | **provenance (`who`) + engine dirty nodes** |
| **M11** | **done** | **Aura-unique features (undo/who/why/blast/time/world/rules/fix)** |
| **M12** | **done** | **the book closes: Soft persist snapshot, open is restore** |
| **M13** | **done** | **`aura` notebook pad, hygienic GAPS, fixture race** |

Acceptance tests for M8–M13: [`ROADMAP.md`](ROADMAP.md).

## 中文

一条规则：**Soft 做所有决定，C 只管像素。** 分层：host（提议脚本、
逐字节对拍模型）→ Soft（世界线/门卫/Propose、编辑模型、高亮跳转与
query/mutate 桥、SNAP 打包与 M7 行缓存、按键表与播放循环）→ C（读
SNAP、失败关闭、上色、转发字节）。SNAP v1 pad 的 `DIRTY` 在 M7 起精确
表示「T/H/M 变了的行 + 光标行」，由 `dirty_check.py` 审计。M7 让每键
只重新分词被编辑的那一行，光标移动只重画含新旧名字的行；整页 12 行
插入从 ~230 ms 降到 ~26–30 ms，光标 ~13 ms。参考 Emacs 算法
（command_loop_1 直接命令、try_cursor_movement、try_window_id、
jit-lock、syntax-ppss 行首状态，见 perf-emacs.md）后插入 ~3.6 ms、
光标 ~1.3 ms。下限是 Soft 解释器
（#4343 每次调用 ~0.2 ms；原地 `vector-set!` ~15 ms，已整理为新
issue 草稿）。诚实规则：拒绝不改、严格更高分才 KEEP、fiber 只在真实
join 时称 live、未绑定的名字写 GAPS 并提 issue、缓存必须等于全量
oracle、性能数字必须由冒烟测得并附“之前”的数字。
