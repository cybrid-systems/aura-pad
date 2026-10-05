# aura-pad design

## Product

A tiny Emacs-like Soft editor that showcases Aura worldlines — not a full
Emacs clone. Soft owns:

- the buffer (list of character codes — FlatAST-friendly),
- the point (integer cursor),
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
- **Propose** — AI proposes a keymap lambda; gate + KEEP only if better.
