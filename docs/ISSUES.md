# aura-pad issues

Live plan: [`ROADMAP.md`](ROADMAP.md). Design: [`DESIGN.md`](DESIGN.md).
M0–M7 stay green.

Aura currently has three open issues. All three were filed from aura-pad.
Pad work does not invent replacements for them.

| Aura issue | What is missing | Pad rule until it lands |
|------------|-----------------|-------------------------|
| [aura#4345](https://github.com/cybrid-systems/aura/issues/4345) | Soft `query:code`, `query:ref-counts`, `query:node-types` unbound | Print `GAPS` those names. Project from the buffer string. Do not wrap. |
| [aura#4344](https://github.com/cybrid-systems/aura/issues/4344) | Soft `define-lookup` unbound | Jump stays Soft HL `pad:goto-def`. `query:defines` / `(query :find)` only. |
| [aura#4343](https://github.com/cybrid-systems/aura/issues/4343) | Per-call cost linear in top-level defines | Do not `set-code` per keystroke. One load per notebook. Smoke budget recorded. Builtin `list-ref` / `list-tail` / `reverse` instead of Soft loops. |
| *(draft, to file)* Soft `vector-set!` / `set-car!` ~15 ms each with the pad loaded (slope ~6× steeper than calls; `out/m7/fill_{0,100,300,600}.aura`) | In-place mutate cost | Never `vector-set!` / `set-car!` on the key path. Rebuild with `list->vector` / `cons`. File from aura-pad after M7 lands. |

#192 and #165 are closed. Do not re-file them. Probe fail is still `ast:snapshot` / `ast:restore`.

## M7 — snappy pad (done)

Shipped as a Soft-side latency increment ([`m7.md`](m7.md)). The earlier
"workspace is the buffer" sketch is now **M9**.

- M7.1 Line cache + exact DIRTY; every frame equals the whole-page oracle (`PAD_M7_TEST_OK`).
- M7.2 DIRTY sound + tight on a Soft play stream (`PAD_M7_DIRTY_OK`); C unchanged.
- M7.3 Twelve-row insert < 50 ms and ≥ 2× vs M6; small page < 50 ms (`PAD_PERF_OK`, `PAD_M7_PERF_OK`). Soft floor published.
- M7.4 `PAD_M7_OK`. M0–M6 markers still print.

## M8 — intent worldline

No new Aura issue. Uses hot-strategy + fibers already on tip.

- M8.1 `pd:goal` slot, ugly pack HEAL.
- M8.2 Two cards in SNAP SAY. C does not pick the winner.
- M8.3 Kind-word gate + capability probe. Unbound capability is a GAP, word-list stays.
- M8.4 Undo KEEP re-scores. Mismatch fails loud. Fixtures: worse DROP, tie DROP, better KEEP.

## M9 — workspace notebook

Blocks on #4345 for a real span projection, on #4343 for load frequency.
Soft DIRTY already landed in M7; engine `query:dirty-nodes` is M10.

- M9.1 Re-probe tip. GAPS line must include the three #4345 names and #4344.
- M9.2 `pad:ws-load!` once per notebook / check (`set-code` + `eval-current`). Project matches `"hi"` / `"  aura"` / `"pad"`.
- M9.3 Keystrokes between checks make zero `set-code` calls. REJECT does not bump generation.
- M9.4 `PAD_M9_OK`. M0–M7 markers still print.

## M10 — who wrote this + engine dirty

`query:dirty-nodes` is a landed name (#344 closed). If unbound on this tip, GAP and Soft DIRTY stays the only source.

- M10.1 Stamp `who/why/gen` from `mutate:summary`.
- M10.2 `who` command (`ctrl-o`). `ast:restore` undo. No guessed text.
- M10.3 Soft DIRTY ↔ engine dirty-nodes cross-check (or `GAPS`).

## M11 — aura notebook

Blocked on #4344 for engine goto-def, #4345 for code/refs/types, #4343 for load cost.

- M11.1 Third pad `aura`. HL tape reused. Jump does not call `define-lookup`.
- M11.2 Hygienic play: missing surface → `GAPS hygienic-play`, no mutate.
- M11.3 Fixture race. Record call cost next to #4343 numbers.

## M12 — book

- M12.1 `std/persist` probe. Unbound → `GAPS persist` + Soft snapshot file.
- M12.2 Open is restore. `who` still answers.
