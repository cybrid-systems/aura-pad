# Aura Pad roadmap

Requirements: [`REQUIREMENTS.md`](REQUIREMENTS.md) · Design:
[`DESIGN.md`](DESIGN.md) · Engine gaps: [`ISSUES.md`](ISSUES.md).

M0–M6 shipped (see `m0.md` … `m6.md`). **M7 shipped** (`m7.md`). M8 shipped (`m8.md`). **M9 shipped** (`m9.md`). **M10 shipped** (`m10.md`). The
earlier M7–M12 sketch in [`NEXT.md`](NEXT.md) (kept for its detail) is
renumbered here; where they disagree, this file wins:
NEXT's "M7 workspace" is now **M9**, "M8 intent worldline" stays **M8**,
"M9 dirty SNAP" + "M10 who" merge into **M10** (Soft DIRTY already landed
in M7). M11–M13 are done (`m11.md`, `m12.md`, `m13.md`).

Why this order: the M6 key path was right at its 50 ms gate (49–54 ms on
a two-row page) and O(page): a twelve-row kid page cost ~230 ms per
insert. A kid editor that lags fails every other requirement first, so
latency went first (M7). The kid-facing game (M8) comes before the
engine-facing workspace (M9) because M9 depends on Aura #4343 / #4345
for load cost and span projection.

## M7 — snappy pad (done)

Line-incremental Soft key path (`soft/pad/lc.aura`), exact DIRTY, list
helpers on builtins. Acceptance (all in `scripts/smoke_m7.sh`):

- [x] Every cached frame equals the whole-page `pad:snap-text` oracle
      byte for byte across the M6 key script, a 12-row edit script
      (type, refused enter, join, split, kill/yank/undo, jump, unclosed
      string fallback), and a > 64-char line (`PAD_M7_TEST_OK`, 147
      checks).
- [x] One insert re-tokenizes exactly one line (`BIG_RETOK_TYPE`); a
      split re-tokenizes two and keeps every shifted row cached.
- [x] DIRTY is sound and tight on a 38-byte Soft play stream
      (`PAD_M7_DIRTY_OK`); unchanged C blits the stream.
- [x] 12-row page: insert < 50 ms/key and ≥ 2× faster than the M6 path;
      small page insert/cursor < 50 ms (`PAD_PERF_OK`,
      `PAD_M7_PERF_OK`).
- [x] M0–M6 markers unchanged; C unchanged.

## M8 — kid onboarding card + intent worldline (done)

Kid opens the pad and sees a two-line welcome card (Soft text in the SNAP
`SAY` / a `CARD` row), then can give a goal (`goal:hi aura`). Two command
helpers race on fibers toward the goal; Soft shows two story cards; the
strictly higher score is KEEP, tie is DROP + `heal!`; undo KEEP re-plays
and re-scores. Hot slot `pd:goal` holds the scoring law; ugly packs HEAL.

New files: `soft/pad/goal.aura`, `soft/pad/card.aura`, `m8_test.aura`,
`m8_smoke.aura`, `scripts/smoke_m8.sh`.

Acceptance tests:

1. `T CARD_FIRST` — first frame of `play.aura` carries the welcome card
   words (Soft strings; C prints them verbatim; `PAD_C_THIN_OK` still
   passes with no new C words).
2. `T GOAL_NONE` — `goal:` with empty text → REJECT `no-goal`, say
   "tell me what the page should say", page unchanged, undo depth
   unchanged.
3. Fixture race: worse helper → `DROP` + `HEAL`; tie → `DROP reason=tie`
   say "same score, keeping yours"; better → `KEEP` and the page equals
   the helper's plan output; `CARD a=.. b=.. KEEP=..` line matches the
   host model (`scripts/goal_model.py`, `PAD_M8_MODEL_OK`).
4. Gate: a proposal containing any banned word or an unkind word never
   enters `pd:goal`; if `capability?` is bound, exec/network/ffi → REJECT
   `not-allowed`, else print `GAPS capability` and keep the word list.
5. `WORLD line=fiber_live joins=2/2` only on real joins; else
   `host-sequential` with the same race result.
6. Undo KEEP restores the previous page and score; a forced mismatch
   fixture fails loud (`PAD_M8_UNDO_FAIL` is never silent).
7. Key path stays under the M7 gates with the card visible
   (`PAD_M7_PERF_OK`). → `PAD_M8_OK`.

## M9 — workspace notebook (done)

The Aura workspace becomes the source of truth for a notebook, but
honestly within #4343: `set-code` + `eval-current` **once per notebook
open / explicit "check"**, never per keystroke. Typing stays on the M7
Soft line cache; a "check" (ctrl-s) pushes the page through `set-code`,
reads `query:defines` / `(query :find)` and shows engine findings as
marks. Edits made by a KEEP (helper/macro/law) go through
`mutate:rebind` inside a boundary; generation bumps once.

New files: `soft/pad/ws.aura`, `soft/pad/pen.aura`, `m9_test.aura`,
`scripts/smoke_m9.sh`.

Acceptance tests (all in `scripts/smoke_m9.sh`, one `M9_ACC n OK` each,
113 checks on Soft tip `c69e644`):

- [x] 1. `pad:ws-load!` calls only `set-code` + `eval-current`; a missing
   name prints `GAPS` and the pad keeps working on the Soft buffer.
- [x] 2. Roundtrip: load → project → load again; projected lines
   byte-equal the M3 line list for `"hi"` / `"  aura"` / `"pad"`, the
   12-row page and a page with an empty row (rows come back from a
   char-code data define, because `query:code` drops comments/layout).
- [x] 3. ctrl-s on the 12-row page: engine names (`define-lookup` per
   candidate) ⊇ Soft find-defs names (missing / extra printed); marks
   `name@row:col`, `query:ref-counts`, `query:node-types` printed; load ms
   printed next to the #4343 / #4350 numbers.
- [x] 4. A REJECTed pen step does not call `set-code`, does not bump
   generation (`mutate:summary :total` unchanged), does not push undo.
- [x] 5. One KEEP rebind bumps generation exactly once; `ast:snapshot` /
   `ast:restore` heals a failed probe (no "transaction" wording).
- [x] 6. Keystrokes between checks make **zero** `set-code` calls (counter in
   `M9STATS`). → `PAD_M9_OK`.

Not shipped: ctrl-s inside `play.aura` (the C SNAP stream). The page's
own `display` output goes straight to stdout and Soft tip has no output
capture, so a check would corrupt the SNAP stream. The `pad:nb-line!`
key handler is tested in Soft only.

## M10 — who wrote this + engine dirty (done)

Every KEEP stamps `(who why gen)` on the rows it touched (`who` ∈ kid,
helper, macro, law; `gen` from `mutate:summary`). Kid key `ctrl-o`
("who wrote this?") answers from the stamp. When
`query:dirty-nodes` is bound, M10 cross-checks Soft DIRTY rows against
engine dirty nodes after a check (M9); unbound → `GAPS query:dirty-nodes`
and Soft DIRTY stays the only source.

Acceptance tests:

- [x] 1. `WHO who=helper why=closer gen=4` on a row a helper KEEP wrote;
   `no-who` "nobody has changed this yet" on an untouched row.
- [x] 2. Kid typing on a stamped row restamps it `who=kid`; undo restores the
   previous stamp with the text (same snapshot).
- [x] 3. Undo of a KEEP is `ast:restore` of the pre-race snapshot + re-project;
   Soft undo stack and restore agree or the test fails loud.
- [x] 4. Engine dirty cross-check: rows of nodes reported dirty ⊆ Soft DIRTY ∪
   cursor row (or `GAPS` line printed). → `PAD_M10_OK`.

Shipped ([`m10.md`](m10.md)): `who.aura` (row stamps, ctrl-o in
`play.aura`), `who_pen.aura` (pen stamps, undo agree check, engine dirty
cross-check). `query:dirty-nodes` is bound on `c69e644`; nodes are
placed on rows through `query:defines` + `query:dirty-subtree` (no node →
row query on tip, so a dirty node outside every page define is printed
as `GAPS query:node-row unmapped=N`, never guessed). Stamps are
row-level; `gen` is read from the engine metrics face (`pad:pen-gen`),
not `mutate:summary`. Filed while building it: #4353.


## M11 — Aura-unique features (done)

Shipped ([`m11.md`](m11.md)): robot undo, engine who, kid why, blast card,
time machine + open-is-restore, sandbox worlds, kid live rules, intend
self-repair. Markers `PAD_M11_UNDO_OK` … `PAD_M11_FIX_OK` live on tip.
Soft tip `c69e644`. Issues filed while building: #4362–#4370.

## M12 — the book closes (done)

Shipped ([`m12.md`](m12.md)). Soft owns persist:

- M12.1 `std/persist` unbound on tip → `GAPS persist`. Soft uses
  `serialize-workspace` / `deserialize-workspace` + `.pad` sidecar
  (`book.aura`). No invented Soft API.
- M12.2 Close / open is restore (no `set-code` guess). Same code/page;
  `who` still answers after open (#4365/#4367 workarounds).
  → `PAD_M12_OK`. Play loop does not load `book.aura` (key latency
  unchanged).


## M13 — aura notebook (done)

Shipped ([`m13.md`](m13.md)). Soft tip `c69e644`.

- Third pad `aura`: sexp + M5 HL tape; Soft jump (+ workspace define-lookup).
- `GAPS hygienic-play` when `clone_macro_body` unbound; refuse mutate.
- Fixture race: failing helper DROPs. → `PAD_M13_OK`.
  Play loop does not load `aura_pad.aura`.

## Latency track (runs alongside M8–M13)

Goal: insert < 16 ms on kid pages (one 60 fps frame). **Met** with the
Emacs ports: insert ~3.6 ms and cursor ~1.3 ms on the twelve-row page on
Aura `c69e644`, down from ~33–35 / 17–19 ms (see `perf.md`,
`perf-emacs.md`). Opening a string above many rows is now under a frame
too: ~7–9 ms (was ~24 ms), the close after it ~6–7 ms (was ~14 ms), via
the syntax-ppss / jit-lock-context region walk. Same-harness vim / Emacs
numbers are in `perf-emacs.md` (they are 10–30× faster per key).

| lever | owner | expected |
|-------|-------|----------|
| Soft call cost independent of define count | Aura #4343 closed, still linear: #4350 | ~3× on every pad path |
| `vector-set!` / `set-car!` O(1) | Aura #4346 closed, still scales: #4350 | lets the cache update in place |
| Load only play-path files in `play.aura` | pad | fewer defines → cheaper calls (measure) |
| Tokenize tape + syms in one pass | pad | done (`pad:lc-scan`): row 15 → 3 ms |
| Emacs ports: direct commands, try_cursor_movement, try_window_id, syntax-ppss carry | pad | done: insert 33 → 3.6 ms, cursor 13 → 1.3 ms |
| Skip SNAP rows C already has (wire v2, still fail closed) | pad + C reader only | done, opt-in `--wire2` (`PAD_WIRE2_OK`): frames 44 → 12 lines, **no latency gain** (cursor 1.86 vs 1.71 ms, insert 3.16 vs 3.24 ms, noise), v1 stays default |

Each lever lands with a before/after line in `perf.md`.

## M18–M24 — sentence line on the live workspace (designed)

Not shipped. The spec is [`sentence-design.md`](sentence-design.md).
M0–M13 stay as they are. M14–M17 window issues are closed.
The next work is the 60 issues in that document, one commit each.
The default binary stays vi until step 21, so today's smoke stays green.
Typing stays on the line cache. A check, and an AI write, happen in a
child workspace. KEEP only when the score is strictly higher.

- M18 — Open a real module, edit, save, and hear one engine sentence.
- M19 — Save the projection, not `query:code`.
- M20 — Who wrote it survives save and reopen, or the pad says soft-only.
- M21 — One sentence is one transaction. Classic mode uses the same card.
- M22 — Two proposals. Show the blast radius before KEEP.
- M23 — A child story uses the same path.
- M24 — Self-repair, and one human-speed rule.
