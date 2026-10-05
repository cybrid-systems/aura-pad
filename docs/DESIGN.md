# aura-pad design

## Product

A tiny Emacs-like Soft editor that showcases Aura worldlines — not a full
Emacs clone. Soft owns:

- the buffer (list of character codes — FlatAST-friendly; from M3 also a
  list of such lines),
- the point (integer cursor; from M3 also `(line col)`),
- a small command table,
- a seeded key sequence.

Kids see short REJECT reasons, not scary jargon. Chinese + English README.

## Aura loop (M0)

1. Build an isomorphic empty buffer for each keymap.
2. Race `map-gentle` and `map-bold` on the **same** seeded keys.
3. Soft gate rejects bad commands before apply; print
   `REJECT mid=.. reason=..`.
4. Score = `edits_ok - 2*rejects - distance_from_goal`.
5. KEEP the strictly higher score; tie keeps gentle.
6. Stamp the winner into the main buffer; DROP the loser (no stamp).
7. `fiber_live` only when both fiber joins return numeric scores,
   `joins == spawned`, and `backend > 0`. Else `host-sequential`.

## Keymaps

| mid | name | moves | insert | delete |
|-----|------|-------|--------|--------|
| 1 | `map-gentle` | ±1, reject `too-far` | printable a–z / space; max len 8 | reject at start (`empty-line`) |
| 2 | `map-bold` | ±3, clamp at ends | looser (same letters, max len 20) | allow when point > 0 |

## Soft reserved

Never use `quote` as an identifier. Prefer `qf`, `mid`, `tag`.

## Roadmap

- **M0** — dual keymap race, Soft gate, KEEP/DROP, honest worldline.
- **M1** — hot-swap keymap pack mid-run (`hot-strategy` ready).
- **M2** — AI proposes a keymap pack lambda; gate + KEEP only if better.
- **M3** — multi-line buffer (`soft/pad/lines.aura`) with `open-line`,
  `kill-line`, `next-line`, `prev-line` and kid reasons `no-line`,
  `too-far`, `empty-buf`. Command-helper propose (`soft/pad/helper.aura`):
  a named Soft lambda in hot slot `pd:helper` returns a command plan; Soft
  gates it, probes it, races it vs main helper `pd:hshadow` on the
  `"hi"`/`"aura"` goal and KEEPs only on a strictly better score, else
  `heal!` + DROP. See [`m3.md`](m3.md).
- **M3.5** — finer commands (`soft/pad/edit.aura`): `undo`, `yank`,
  `indent`/`dedent`, `bob`/`eob`, `set-mark`, `kill-region`,
  `copy-region`, each with a kid reason; `say="..."` on REJECT, `SCORE`
  breakdown; three-line goal for the helper race via scoring hooks;
  `pd:helper-undo!` takes back a KEEP with an honest re-score. Tests:
  paren check, Python model, Soft unit tests. See [`m35.md`](m35.md).
- **M4** — kid story editor (`soft/pad/m4.aura`, `soft/pad/macro.aura`):
  two named pads (`story` / `scratch`), find / find-next / replace /
  replace-all with kid reasons (`not-found`, `empty-needle`, `too-many`,
  `not-kind`), `rec` / `stop` / `play` macros, a buffer-law race (two laws
  on the same keys, KEEP stamps the law into main) and macro propose (hot
  slot `pd:macro` vs `pd:mshadow`, kind-word gate, race on the story goal,
  KEEP only strictly better, `heal!` on DROP, `pd:macro-undo!`). Tests:
  Python model, 293 Soft checks. See [`m4.md`](m4.md).

## M3 layering

```
buffer.aura   M0 chars, gate, sim (unchanged)
rules.aura    race-thunks!, WORLD line (unchanged)
pack.aura     M1/M2 keymap pack (unchanged, not loaded by M3)
hot.aura      M1/M2 hot slot + gate words (reused by M3)
lines.aura    M3 lines, (line col), line ops, plans, pure lsim, stamp
helper.aura   M3 pd:helper / pd:hshadow propose → gate → race → KEEP/DROP
              (M3.5: scoring hooks, KEEP history, pd:helper-undo!)
edit.aura     M3.5 edit state (kill, mark, undo), finer commands, esim,
              goal3, TAPE view / SCORE, pad:helper-use-goal3!
m4.aura       M4 pad state (story / scratch, needle, recorder, law), find /
              replace / switch / rec / stop / play, pure msim, story goal,
              two-pad TAPE, pad:law-race!
macro.aura    M4 pd:macro / pd:mshadow propose → gate (code + kind words) →
              probe → race → KEEP/DROP, KEEP history, pd:macro-undo!
```

Honesty rules (M3.5): a REJECT never mutates and never pushes undo; undo
restores a recorded snapshot, never a guess; world undo re-plays and
re-scores the restored helper and fails loudly on a mismatch.

Honesty rules (M4): a refused token never mutates (also inside `play`,
where each step is gated again and refusals count); a law is stamped into
main only after a strictly better race; a macro body with an unkind word
never reaches a slot; `fiber_live` only when every join lands.
