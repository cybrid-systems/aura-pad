# aura-pad issues (M7–M12)

Design: [`NEXT.md`](NEXT.md). M0–M6 stay green.

Aura currently has three open issues. All three were filed from aura-pad.
Pad work does not invent replacements for them.

| Aura issue | What is missing | Pad rule until it lands |
|------------|-----------------|-------------------------|
| [aura#4345](https://github.com/cybrid-systems/aura/issues/4345) | Soft `query:code`, `query:ref-counts`, `query:node-types` unbound | Print `GAPS` those names. Project from the buffer string. Do not wrap. |
| [aura#4344](https://github.com/cybrid-systems/aura/issues/4344) | Soft `define-lookup` unbound | Jump stays Soft HL `pad:goto-def`. `query:defines` / `(query :find)` only. |
| [aura#4343](https://github.com/cybrid-systems/aura/issues/4343) | Per-call cost linear in top-level defines | Do not `set-code` per keystroke. One load per notebook. Smoke budget recorded, not ignored. |

#192 and #165 are closed. Do not re-file them. Probe fail is still `ast:snapshot` / `ast:restore`.

## M7 — workspace is the buffer

Blocks on #4345 for a real span projection, on #4343 for load frequency.

- M7.1 Re-probe tip. GAPS line must include the three #4345 names and #4344.
- M7.2 `pad:ws-load!` once per notebook (`set-code` + `eval-current`). `pad:ws-project` matches `"hi"` / `"  aura"` / `"pad"`.
- M7.3 `pad:pen-insert` / `pad:pen-delete` under a mutation boundary. REJECT does not bump generation.
- M7.4 `PAD_M7_OK`. M0–M6 markers still print.

## M8 — intent worldline

No new Aura issue. Uses hot-strategy + fibers already on tip.

- M8.1 `pd:goal` slot, ugly pack HEAL.
- M8.2 Two cards in SNAP SAY. C does not pick the winner.
- M8.3 Kind-word gate + capability probe. Unbound capability is a GAP, word-list stays.
- M8.4 Undo KEEP re-scores. Mismatch fails loud. Fixtures: worse DROP, tie DROP, better KEEP.

## M9 — dirty SNAP

`query:dirty-nodes` is a landed name (#344 closed). If unbound on this tip, GAP and full SNAP. Do not use #4345 names to fake dirtiness.

- M9.1 `soft/pad/dirty.aura` bridge.
- M9.2 `SNAP v1 pad-dirty`. C fail-closed. `PAD_C_THIN_OK`.

## M10 — who wrote this

- M10.1 Stamp `who/why/gen` from `mutate:summary`.
- M10.2 `who` command. `ast:restore` undo. No guessed text.

## M11 — aura notebook

Blocked on #4344 for engine goto-def, #4345 for code/refs/types, #4343 for load cost.

- M11.1 Third pad `aura`. HL tape reused. Jump does not call `define-lookup`.
- M11.2 Hygienic play: missing surface → `GAPS hygienic-play`, no mutate.
- M11.3 Fixture race. Record call cost next to #4343 numbers.

## M12 — book

- M12.1 `std/persist` probe. Unbound → `GAPS persist` + Soft snapshot file.
- M12.2 Open is restore. `who` still answers.
