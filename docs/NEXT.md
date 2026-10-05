# aura-pad M7–M12

Next editor after M6. Not an Emacs clone and not a chat sidebar.
Soft still owns meaning. Aura workspace becomes the buffer. C stays a
blitter. Kids get story cards and short reasons. Aura development gets a
real client for `query:*` / `mutate:*` / hot-strategy / dirty / persist.

M0–M6 files and smoke markers stay green. New work lives in new files.

Honesty, carried forward:

- A REJECT never mutates and never pushes undo.
- KEEP only on a strictly better score. Tie is DROP (M0 gentle-tie is
  the only exception, and it stays in M0).
- `fiber_live` only when every join lands, `joins == spawned`, backend > 0.
- Unbound tip names are GAPS, filed on `cybrid-systems/aura` from
  aura-pad. No fake Soft wrappers.
- If C would need to know what a key, a word, or a character means, that
  logic belongs in Soft.
- Until Aura ships `mutate:atomic-batch` (#192), a failed probe is
  `ast:snapshot` + `ast:restore` (or the existing `heal!`). Do not claim
  a transaction.

## Two notebooks, one pen

| pad | who | projection | score |
|-----|-----|------------|-------|
| `story` | kid (fruit lesson) | sentences | closer to goal, fewer rejects, kind words |
| `scratch` | try-and-drop | same pen | not stamped |
| `aura` | Aura author | sexp + HL tape | typecheck + fixture tests + fewer rejects |

`story` / `scratch` already exist (M4). `aura` arrives in M11. Same gate,
same KEEP/DROP, same SNAP family.

## Stack

```
key or goal
    |  Soft gate (kind words, shape, capability)
    v
hot slot lambda  --fiber-->  shadow worldline
    |                         |
    v                         v
Aura workspace: query reads, mutate writes, generation bumps once
    |
    v
project: lines + HL tape + def/use marks + who/why + kid SAY
    |
    v
SNAP v1 pad  (M9 adds a dirty block; C still fail-closed)
    |
    v
C blit / byte forward only
```

New Soft files (do not rewrite M0–M6 owners):

```
soft/pad/ws.aura       M7 set-code workspace, project lines, roundtrip
soft/pad/pen.aura      M7 keystroke -> mutation boundary insert/delete
soft/pad/goal.aura     M8 pd:goal slot, story-card race, SCORE
soft/pad/dirty.aura    M9 query:dirty-nodes bridge, dirty SNAP block
soft/pad/who.aura      M10 provenance tape, kid ask, restore undo
soft/pad/aura_pad.aura M11 third notebook, hygienic play, tip query only
soft/pad/book.aura     M12 persist save/load
```

## What Aura already gives us

Use only tip-bound surfaces (probed in M5, tip `73c012c` era; re-probe
on the image before coding). Landed and useful:

| surface | pad use |
|---------|---------|
| `set-code` + `eval-current` | load a notebook into the workspace (`pad:q-load!`) |
| `query:list-categories` / `query:help` | kid "what can I ask" |
| `(query :find)` / `(query :def-use)` | jump / refs, already bridged |
| `query:defines` / `query:find-by-name` | "where is this name born" |
| `mutate:rebind` | helper / macro / law stamp |
| `mutate:summary` / `mutate:boundary-safe?` / `mutate:boundary-depth` | SCORE and SAY |
| `std/hot-strategy` `hot-strategy:swap!` | `pd:law` `pd:helper` `pd:macro`, later `pd:goal` |
| `ast:snapshot` / `ast:restore` | probe, heal, undo |
| `query:dirty-nodes` | M9 dirty block (reason bit, node ids) |
| `std/persist` | M12 book |
| capability `Mutate` vs no exec/network/ffi | M8 gate, replaces the word-list as source of truth once probed |

Known GAPS (do not wrap): `define-lookup`, `query:code`, `query:ref-counts`
(exported, unbound at call), `query:node-types`. Soft HL goto-def stays
the fallback until Aura binds a real lookup.

Do not wait on #192 (`mutate:atomic-batch`) or #165 (hygienic re-expand
after `mutate:*`). Pad issues file the editor-shaped gaps; Aura issues
track the engine holes. Pad ships on snapshot/restore meanwhile.

## M7 — workspace is the buffer

Char-code lines stay the projection, not the source. A notebook string
enters through `set-code`. Soft projects FlatAST-backed text back to the
M3 line list + `(line col)` point. Editing a letter is a bounded mutate,
not a list poke.

Kid story: open `story`, type `h`, see `h`. Undo puts the page back.
Nothing about AST is said out loud.

Aura payoff: pad becomes a client of the workspace. Every later milestone
reads nodes, not a parallel string.

Smoke: `PAD_M7_OK`. Host model byte-matches Soft. Paren check stays.

Acceptance:

- `pad:ws-load!` calls `set-code` + `eval-current` only. Missing either
  name is a GAP line, not a fake.
- `pad:ws-project` returns the same line list the M3 buffer would show
  for the fixture `"hi"` / `"  aura"` / `"pad"`.
- Roundtrip: project, do not edit, project again, bytes equal.
- `pad:pen-insert` / `pad:pen-delete` take a mutation boundary. REJECT
  (`too-far`, `not-print`, `empty-line`) does not bump generation and
  does not push undo.
- One successful insert bumps generation once (read `mutate:summary`).
- M0–M6 smokes still print their `PAD_*_OK` lines.

Out of scope: AI propose, dirty SNAP, third notebook.

## M8 — intent worldline (the kid game)

Kid does not get a ghost completion. Kid gives a goal (`"hi"` / `"aura"`
or the M4 story fixture). Two helpers race on fibers. Soft shows two
story cards. Strictly higher score KEEP. Tie DROP + `heal!`. Undo KEEP
re-plays and re-scores; mismatch fails loud (M3.5 rule).

Hot slot `pd:goal` holds the scoring law `(step room strict kind)`,
swapped with `hot-strategy:swap!`. Ugly packs HEAL, same as M1.

Score, story mode:

```
edits_ok - 2*rejects - distance_from_goal - 4*unkind
```

Score, aura mode (M11, hook only here):

```
edits_ok - 2*rejects - distance_from_goal - 8*typecheck_fail
```

Cards are Soft text, packed into the existing SNAP SAY/LEGEND area:

```
CARD a=31 b=27 KEEP=a say="a is closer"
```

C prints the line. C does not pick the winner.

Kid reasons added: `no-goal` "tell me what the page should say",
`tie` "same score, keeping yours", `not-kind` (already M4).

Smoke: `PAD_M8_OK`. Fixtures: worse DROP, tie DROP, better KEEP, undo
KEEP restores the old score. Live MiniMax stays behind `PAD_LIVE`
(host `scripts/propose_minimax.py`), same as M2–M4.

Acceptance:

- Gate words: no `set!` `display` `eval` `load` `shell` `http`, plus
  kind-word list. Rejected lambda never enters the slot.
- `WORLD line=fiber_live` only on real joins. Else `host-sequential`
  and the race result is still honest.
- Capability probe: if `capability?` `Mutate` is bound, a proposal with
  exec/network/ffi is REJECT `not-allowed` before the race. If unbound,
  word-list gate remains and a GAP line is printed.

## M9 — dirty SNAP

`query:dirty-nodes` (landed with #344, reason bit, smallest-first node
ids) drives a dirty block. Full `SNAP v1 pad` still emitted when the
client asks or when the query is a GAP. New block, same family:

```
SNAP v1 pad-dirty
lines=<n> gen=<g>
<line-no> <text>
HL <tape>
END
```

C (`c/snap.c`) accepts the block, fail-closed, last complete block wins.
C does not interpret the reason bit. Missing `query:dirty-nodes` prints
`GAPS query:dirty-nodes` and falls back to a full SNAP. Do not invent
the query.

Smoke: `PAD_M9_OK`, `PAD_C_THIN_OK` still holds (no edit logic in C).

## M10 — who wrote this

Each KEEP stamps a provenance triple onto the touched span:

```
who   kid | helper | macro | law
why   reason string already used in REJECT/SCORE
gen   generation from mutate:summary
```

Kid command `who` under the cursor:

```
WHO who=helper why=closer gen=4
say="the helper wrote this"
```

Empty span: `no-who` "nobody has changed this yet".

Undo of a KEEP is `ast:restore` of the snapshot taken before the race,
then re-project. Soft undo stack remains for keystroke pens until M7
pen and M10 restore agree on one stack. Mismatch fails loud.

Smoke: `PAD_M10_OK`.

## M11 — aura notebook

Third pad `aura`. Projection is sexp. HL tape is the M5 tape (`P K S T C
Q M N`). Jump uses Soft HL goto-def until a real lookup is bound; also
calls `query:defines` / `query:find-by-name` when the workspace is loaded.

`play` of a recorded macro re-gates every step (M4 rule) and, when the
body is Aura syntax, runs through hygienic expand before mutate. If
`clone_macro_body` is not a Soft-visible name, print
`GAPS hygienic-play` and refuse to mutate (do not capture kid names).
This is the pad-side pressure on Aura #165, not a reimplementation.

`mutate:rebind` remains the only write used for "rename this define".
Multi-site replace waits for #192; until then snapshot, rebind, restore
on probe fail.

Smoke: `PAD_M11_OK`. Fixture:

```
(define (hello x) (+ x 1))
(hello 3)
```

goto-def still lands on the binding. A proposed helper that fails the
fixture scores lower and DROPs.

## M12 — the book closes

`std/persist` saves the workspace + mutation log. Open is restore, not
"read text and guess". If `persist` is unbound in the image, print
`GAPS persist` and write a Soft-side snapshot file the next milestone
can swap. Do not invent an AURASOUL writer.

Kid story: close the pad, open it, the story is the same story, `who`
still answers.

Smoke: `PAD_M12_OK`.

## Issue split

Pad issues live in `cybrid-systems/aura-pad`. Engine holes live in
`cybrid-systems/aura` with `Filed from: aura-pad`.

Pad:

- M7 parent + load/project, pen, roundtrip, smoke
- M8 parent + goal slot, race + cards, gate/capability, undo rescore
- M9 parent + dirty bridge, SNAP block, C fail-closed
- M10 parent + stamp, who command, restore undo
- M11 parent + aura notebook, hygienic play gap, fixture race
- M12 parent + persist probe, open-is-restore

Aura (file, do not fake in pad):

- Bind `query:ref-counts` (exported, unbound at call).
- Editor projection: source span for a node id (`query:code` or equivalent).
- Bind `query:node-types` or delete it from docs.
- Dirty span with line/col, not only node id, for SNAP (extends #344).
- Do not re-file #192 or #165; pad issues link them.

## 中文

M7 起缓冲区的真身是 Aura 工作区，字符行只是投影。敲一个字是一次有边界的
mutate，拒绝不改、不加 generation。M8 是孩子玩的部分：给目标，两条世界线
赛跑，两张故事卡，严格更高分才 KEEP，平局 DROP，撤销会重打分。M9 用
`query:dirty-nodes` 只打包脏行，没有这原语就退回整页 SNAP。M10 每个 KEEP
盖 who/why/generation，孩子问「谁写的」读盖章，不让模型再编。M11 加 `aura`
本子，宏回放走 hygienic，引擎没有就把 `GAPS hygienic-play` 打出来并拒绝
写入。M12 用 `std/persist` 存读，打开是 restore。C 始终只上色、只转发字节。
