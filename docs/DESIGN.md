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

## M3 layering

```
buffer.aura   M0 chars, gate, sim (unchanged)
rules.aura    race-thunks!, WORLD line (unchanged)
pack.aura     M1/M2 keymap pack (unchanged, not loaded by M3)
hot.aura      M1/M2 hot slot + gate words (reused by M3)
lines.aura    M3 lines, (line col), line ops, plans, pure lsim, stamp
helper.aura   M3 pd:helper / pd:hshadow propose → gate → race → KEEP/DROP
```
