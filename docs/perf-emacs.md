# Emacs algorithms in the aura-pad key path

The user asked: 性能相关的参考下 emacs 的对应算法 (for performance work,
borrow Emacs's matching algorithms). This page maps each Emacs algorithm
we looked at to the Soft code that ports it, with measured before/after
numbers. Soft still owns every edit and highlight decision, and C only
blits. Each fast path is checked against a reference path or the
whole-page oracle on every frame (`soft/pad/emacs_test.aura`).

```bash
bash scripts/smoke_perf.sh   # PAD_PERF_OK, PAD_M7_PERF_OK, then PAD_PERF_EMACS_OK
bash scripts/run_soft.sh /workspace/aura-pad/soft/pad/perf_probe.aura   # PROBE breakdown
```

Emacs sources cited: GNU Emacs master (`emacs-mirror/emacs` 9bc5661e),
plus Emacs 22.3 `keyboard.c` for the old direct-command loop. Soft
binary: `/workspace/aura-grok/build/aura`, Aura tip `c69e644`. The box
is shared with other agents, so expect ±20–30% wall-clock noise.

## Where a key's time goes (measured first)

Per-op cost inside Soft, in µs per loop iteration (`out/emacs/r4350_*.aura`,
`out/emacs/op1.aura`):

| op | 0 defines | 300 filler defines | 1000 filler defines | pad loaded |
|----|-----------|--------------------|---------------------|------------|
| named-let step | 8 | 11–17 | 17 | 11 |
| 10 primitive `+` (net of the step) | 24 | 34–57 | 60 | 35 |
| call a user procedure `(f0)` (net) | ~80–87 | ~210–310 | ~560 | ~250 |

So one key costs about **0.25–0.3 ms per Soft procedure call** plus
**~3–6 µs per primitive op**. Buffer work is tiny: a kid line has at most
~40 codes, and a builtin `append` or `drop` on it costs microseconds. The
M7 path spent its time on *calls*. Tokenizing one row took ~50 helper
calls (char class, kind, run, syms…), so a row cost ~15 ms. Every port
below either removes calls (inline the helper as builtin expressions) or
skips work the way Emacs redisplay does.

Outside Soft (measured, small):

| piece | cost |
|-------|------|
| C `pad_view` parse of one SNAP block | ~1.6 µs |
| C exec + parse 201 blocks + blit | ~1 ms (once per process in the smoke; `pad_play` keeps one process) |
| Docker + Soft start + pad load | ~0.8–1.1 s, **once** per session, not per key |
| headless end-to-end `soft_play` (read line → cmd → SNAP → stdout), 200 keys | insert **10.4 → 3.6 ms/key**, cursor **16.3 → 3.0 ms/key** (start page; the SNAP streams are byte-identical old vs new) |

## Ported algorithms

µs per key on the twelve-row M7 page, harness subtracted
(`perf_probe.aura`; BEFORE = tree `bbc7c04` with the same probe, AFTER =
this tree; two runs each, `out/emacs/probe_final.txt`).

| # | Emacs (file / function) | What Emacs does | aura-pad Soft (file / function) | before µs | after µs |
|---|---|---|---|---|---|
| 1 | `src/keyboard.c` `command_loop_1` (22.3: forward-char, backward-char and self-insert-command run *directly*, everything else goes through `call-interactively`); `src/cmds.c` `internal_self_insert` | The hottest commands skip the generic dispatch | `keys.aura` `pad:play-cmd!`: inline arms for chars, left/right/home/end, next/prev-line, open-line, enter, back (join and in-line). Undo push is inlined. Every other command goes to `pad:play-cmd-ref!` (the old dispatch) | cmd insert 9 300–9 600 | **620–650** |
| 2 | `src/xdisp.c` `try_cursor_movement` | Point moved and the text did not change: reuse the whole current matrix and just move the cursor | `keys.aura` `pad:play-snap`: the same lines object and the same name under the cursor → reuse the cached rows and the joined SNAP body `*lc-body*`, so DIRTY = cursor row. A name change goes to `lc.aura` `pad:lc-move-to!` (mark rows only) | cursor 13 000–14 200; SNAP with no change 4 100–4 500 | **1 320–1 350**; **690** |
| 3 | `src/xdisp.c` `try_window_id` (+ `try_window_reusing_current_matrix`) | Redisplay only the changed rows; find unchanged rows above and below, including rows shifted by inserted/deleted lines | `lc.aura` `pad:lc-line!` (one-row edit), `pad:lc-entries` (match each row at shift d, 0, −1, +1) and `pad:lc-fast-recs` (a kept row reuses its old row string) | insert 32 000–33 600; enter/join 32 000–36 500 | **3 570–3 620**; **5 400–7 300** |
| 4 | `lisp/jit-lock.el` `jit-lock-fontify-now`, `jit-lock-function` | Fontify only the region that needs it, in one pass | `lc.aura` `pad:lc-scan`: one pass yields tokens, HL tape, symbols and the carry. Char class (`*lc-cls*` + `string-ref`) and token kind are inline, and tape runs are slices of prebuilt run strings (`*lc-run-*`, built by doubling) | tokenize one row 14 500–14 700 | **3 240–3 300** |
| 5 | `lisp/jit-lock.el` `jit-lock-after-change` | Mark text unfontified only from the change start | `lc.aura` `pad:lc-line!`: verify the unchanged prefix `[0, col-1)` with `substring`, keep the tokens that end before it, and resume `pad:lc-scan` there | (in #3) | (in #3) |
| 6 | `lisp/emacs-lisp/syntax.el` `syntax-ppss`; `jit-lock.el` `jit-lock-contextually`, `jit-lock-context-fontify` | Cache the parse state per position; refontify later lines only when their syntactic context changed | `lc.aura`: entry field `ins` (the line starts inside a string). `pad:lc-scan` takes it as the start state; `pad:lc-entries` matches on (codes, ins); `pad:lc-line!` goes generic only when the row's end state flips. **This replaces M7's whole-page fallback** | type inside an open string 217 000–223 000; open + close string 158 000–159 000 (avg per key) | **3 400–3 750**; **13 700–13 900** |
| 7 | `lisp/emacs-lisp/syntax.el` `syntax-ppss` cache (`syntax-ppss-wide`: state memoized per position, reused while the text before it is unchanged) | Do not recompute a parse state you already computed | `lc.aura` record field 5 `alt`: the same row text lexed from the *other* start state, with its mark row and row string (a per-row ppss memo). `*lc-tail*`: the rows below an edit as they were before their start state flipped, checked by content (codes, state, carry, name) and reused whole. Closing a string you just opened, or opening it again, gets every row below back without a re-lex. `*lc-hint*`: the row `pad:lc-line!` already scanned is not scanned again | close after open 10 800–11 500 | **5 600–6 300** |
| 8 | `lisp/jit-lock.el` `jit-lock-context-fontify` / `jit-lock--run-functions` (refontify from the change only as far as the syntactic context differs; stop when a line's state matches) | Walk the lines after a change while their start state differs, then stop | `lc.aura` `pad:lc-line!` region walk: row l is re-lexed from the change; each row below is touched only while its start state (inside a string?) or def-carry differs from what its cached record was built with, and the walk **stops at the first row that matches**. Touched rows take, in order: the cached record (same state), the record's `alt`, the tail memo, a direct one-token build for a quote-free row now inside a string (`pad:lc-entry2`, builtin `string-index`, no per-char scan), else one scan. No generic frame on a string flip any more | first string open 20 000–20 600 (25 000–28 000 noisy); typing inside a name 13 500 | **7 000–7 900**; **8 600–9 000** |
| — | mark rows (pad, no Emacs analogue) | — | `pad:lc-remark!` with inline mrow (slices only at matching tokens) | cursor onto a name used on 5 rows: 34 600–34 700 | **6 900–7 700** |

`perf.aura` gates on the same tree: small page insert / cursor
39 / 18 ms → **4–5 / 3 ms**. Twelve-row insert / cursor 34 / 21 ms →
**4–5 / 3–4 ms**. Command only 7 ms → **0.6 ms**.

Rows 7–8: A/B on the same box and probe (`out/m10/ab_A.aura` = tree
`2b4ca35`, `ab_B.aura` = this tree, five interleaved runs,
`out/m10/ab1.txt`, `ab2.txt`). Insert and cursor are unchanged within
noise (A 3 600–3 700 / 1 300–1 400, B 3 700–3 900 / 1 300–1 500).
`emacs_test` gate run inside the full smoke: `open_first_us` 7 666–9 333,
`close_after_open_us` 6 333–7 000. Both are now gated < 16 000 µs.

Correctness (`emacs_test.aura`, 43 checks, all part of `smoke_perf.sh`):

- `pad:play-cmd!` equals `pad:play-cmd-ref!` on seeded random streams over
  four pages: same result, state, key count, rejects and say text.
- `pad:lc-scan` equals the M6 tokenizer and colorer on whole pages and on
  per-line chains that carry the start state.
- Random typing (quotes, comments, enter, backspace, moves): every frame
  equals the whole-page oracle `pad:snap-text`.
- Quote-heavy random typing on the twelve- and nine-row pages (strings
  open and close every few keys): every frame equals the oracle.
- Opening and closing a string matches the oracle; the close and a
  re-open re-lex at most one row (`ALT_CLOSE_RETOK`,
  `MEMO_REOPEN_RETOK`, `CLOSE_ROW1_RETOK`). A def-carry change stops the
  walk one row later (`CARRY_STOP_RETOK`). The direct no-quote entry
  equals `pad:lc-scan` (`TRIV_ENTRY`).

The existing 147 M7 checks and the host DIRTY audit still pass.

## Rejected (and why)

| Emacs | why not here |
|-------|--------------|
| Gap buffer: `src/insdel.c` `gap_left`, `gap_right`, `make_gap`, `insert_1_both` | It wins on big buffers by not moving bytes. Kid lines are ≤ 40 codes, and the line splice is a few builtins (tens of µs). The cost is per Soft *call*, not per byte. The whole insert command is now 0.6 ms. |
| `src/marker.c` `buf_charpos_to_bytepos` (CONSIDER on PT, GPT, markers, cached_charpos) | No multibyte split: one code is one char. The (line, col) ↔ offset mapping (`pad:v-point`) only runs for jump, never per key. |
| Undo amalgamation: `lisp/simple.el` `undo-auto-amalgamate`, 22.3 `nonundocount` 20 | It changes what one undo restores, and kid tests expect one undo per key. The push is already one `cons` + `take`. |
| `jit-lock-defer-time`, `jit-lock-stealth-*`, `jit-lock-context-time` (deferred refontify) | Every SNAP must equal the oracle (oracle tests, DIRTY audit). A deferred frame would paint stale colors. This is the one place Emacs is lazier than us: it refontifies the lines after an unclosed `"` only after 0.5 s idle. |
| `display-line-numbers`, `src/xdisp.c` `display_count_lines` | The pad shows no line numbers. |
| `direct_output_for_insert` (22.3 `dispnew.c`) as a C fast path | That would put edit knowledge into C. Soft does the equivalent instead (#1 + #3). |

## Honest floor

A twelve-row insert now costs about 3.6 ms:

- ~4 Soft calls (`play-cmd!`, `play-snap`, `lc-line!`, `lc-scan`) ≈ 1.1 ms;
- re-lexing the row tail ≈ 0.5 ms;
- the rest is ~5 µs primitives: the one-row check (`drop`/`reverse`/`equal?`), record rebuild, codes → string, SNAP string.

A cursor key costs ~1.3 ms, which is about 4–5 calls. Opening a string
on line 5 of 12 now costs ~7–8 ms (was ~20–24 ms): the region walk still
touches the seven rows below once each, but a quote-free row costs a few
builtins instead of a scan, and nothing else is rebuilt. Closing it again
is ~6 ms (was ~11–14 ms): the tail memo brings the rows back whole, so
the cost is row l plus the dirty walk. Both are under one 60 fps frame,
not yet at the ~4 ms of a plain insert. What is left is the per-row walk
(~0.3–0.5 ms per touched row in named-let steps and list building) and
the name-under-cursor remark.

Soft scoping on c69e644 bit this work: an outer local captured inside a
named-let body can resolve to a same-named global (the first version of
the walk read std/math's `e` instead of the local entry). The walk's
local is named `le` (Aura #4353).

The remaining floor is Aura's per-call cost (#4350: calls *and*
primitives get slower as the program defines more names). Removing that
would cut these numbers about 3× again.

## Same-harness comparison with vim and Emacs

`scripts/bench_editors.sh` runs all three editors on this box, inside
the same container, on the same twelve-row file (byte-identical to
`*lc-big-page*`), cursor at the end of row 6, through one pseudo-terminal
each (`scripts/latency_pty.py`, 80×24, `TERM=xterm-256color`). It times
keystroke write → the editor's terminal output: `first` = first byte,
`done` = last byte before 60 ms of quiet. Each key is followed by its
undo key (`a`/backspace, left/right). The string test (`"` then
backspace) also waits 1.2 s for deferred output.

```
bash scripts/bench_editors.sh | tee out/bench/editors.txt   # not a smoke
```

Medians, two runs (`out/bench/editors.txt`, 2026-10-06, vim 9.2,
GNU Emacs 30.2, pad = `pad_play --ansi` → Soft `play.aura`):

| ms per key (done) | aura-pad | vim `-u NONE`, syntax on | `emacs -nw -Q` (font-lock) |
|---|---|---|---|
| insert | 7.9 / 8.2 | 0.34 / 0.32 | 0.65 / 0.67 |
| cursor | 6.8 / 7.0 | 0.23 / 0.26 | 0.60 / 0.64 |
| string open (`"`) | 8.3 / 8.7 | 0.44 / 0.45 | 0.90 / 0.96 |
| string close (backspace) | 12.3 / 10.1 | 0.41 / 0.49 | 0.59 / 0.48 |

What this does and does not show:

- vim and Emacs are **10–30× faster per key** than aura-pad on this box.
  aura-pad is under one frame; it is not close to them.
- It measures bytes on a pty, not photons. Every editor here draws
  differently: vim and Emacs send minimal cursor-addressed updates, the
  pad sends a full SNAP block through a pipe to `pad_play`, which parses
  and redraws. The pad number includes the Soft read loop, the
  escape-sequence decode (an arrow key is three `IN` lines, two of them
  `pending`), the SNAP `display`, the pipe and the C parse + blit. The
  in-Soft numbers above (insert ~4 ms, cursor ~1.3–1.7 ms) exclude all
  of that, which is why they are lower than the pty numbers.
- The work per key is not the same. The pad recomputes HL letters and
  def/use marks for the name under the cursor and checks every frame
  against an exact model; vim's regex syntax and Emacs's font-lock do
  their own (different) amounts of work.
- Emacs defers contextual refontification after an unclosed `"`
  (`jit-lock-context-time`, 0.5 s). In this run no extra output arrived
  within 1.2 s (`all_output` = `done`), so the 0.9 ms Emacs number covers
  only the immediate redisplay.
- One key of vim's left/right cursor pair produced no terminal output,
  so only half of vim's cursor samples are counted (n=60 of 120).
- `emacs -Q --batch` timing of `self-insert-command` + `redisplay` is
  **not** comparable (batch mode has no real redisplay), so it is not
  used.
