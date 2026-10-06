# Aura-native perf: what Aura gives the pad key path, and what it does not

The user asked (in Chinese) for another look at perf with three goals:
use Aura's incremental compilation fully, hide computation with fibers
and similar tools, and look for optimisations unique to Aura, that a
C/Rust native editor cannot do. This page records what was measured on
Soft tip `c69e644`, what shipped, and which negatives held up.

```bash
bash scripts/smoke_aura_perf.sh     # PAD_AURA_PERF_OK (also run by smoke.sh)
BENCH_RUNS=2 bash scripts/bench_editors.sh > out/bench/editors_aura.txt   # pty, not a smoke
```

Every surface named here was called on the tip. Probes are in
`out/aura-perf/p/` (not committed). `soft/pad/aura_facts.aura`
(`PAD_AURA_FACTS_OK`) re-checks the claims the design relies on, so this
page fails loud if Soft changes. Nothing was added to or renamed in the
engine's observability counters.

## 1. Research: the surfaces and what they cost

### Incremental compilation / relower / workspace

| surface | on the tip, called from a pad file | measured |
|---|---|---|
| `set-code` + `eval-current` | creates the workspace AST. Before that, file mode has **none** | M9 does it once per check |
| `define-lookup` | `(no-workspace ...)` in file mode (F_NO_WORKSPACE); a record after set-code (line/col 0, #4347) | — |
| `mutate:rebind name body why` | swaps a workspace define; its callers see the new body (F_REBIND) | **12–18 ms** per rebind, one outlier at 57 ms |
| `ast:snapshot` / `ast:restore` + `eval-current` | rolls a rebind back (F_RESTORE; heals #4349) | restore + eval 1–3 ms |
| `engine:metrics "query:incremental-relower-stats"` | 285-key hash. `query:incremental-relower-stats` called directly is unbound | — |
| `engine:metrics "query:dirty-cascade-stats"` / `"query:soa-dirty-stats"` | bound | read only |
| `query:dirty-nodes "general"` | node ids dirtied by the last mutation, e.g. `(5 11)` after one rebind. M10 already cross-checks it against Soft DIRTY | — |
| `compile:relower-strategy name` | keyword `:none` / `:incremental` / `:full` (`:none` for a lambda define) | — |
| `query:last-epoch` | unbound | — |
| `std/hot-strategy` (`swap!`, `heal!`, `call`) | snapshot + rebind + eval-current | same 12+ ms rebind |

A workspace define called from file code, or a loop inside one, runs
at **the same speed as file code** (`p/wsloop.aura`). Rebind/relower is
a semantic hot swap. On this runner it does not buy IR or JIT
specialisation, so there is nothing to make faster with it.

### Fibers

| surface | on the CLI runner |
|---|---|
| `fiber:spawn-backend` | `2` = OS-thread fallback (the cooperative scheduler exists only under serve-async) |
| `fiber:spawn` + `fiber:join` | ~0.2 ms overhead. Real parallelism: two allocation-heavy works take 558 ms in sequence and 326 ms in parallel (1.7×) |
| `fiber:yield` | no-op outside serve-async |
| `eval:async` | falls back to synchronous eval |

**Safety.** The main thread does not take the fiber body mutex.
`read-line` pushes onto the string heap without the lock. So a fiber
that allocates strings while main waits in `read-line` (the pad's main
loop) corrupts strings or SIGSEGVs. Filed as
[aura#4356](https://github.com/cybrid-systems/aura/issues/4356)
(repro `p/race_rl.aura` + `gen.py`; the control without `read-line` is
clean). The only safe pattern for the pad is spawn → join with main
idle, and that hides nothing. Running the pad's keys inside a fiber
gained nothing (`p/fprof.aura`: an insert+undo pair took 6.6–6.9 ms vs
6.6–8.9 ms on main).

There is also no non-blocking stdin poll in Soft (no `char-ready?`), so
the main thread cannot do idle work between keys either.

## 2. Design: candidates, and which shipped

| idea | verdict | why |
|---|---|---|
| **Early frame + exact settle** (`PAD_DEFER=1`) | **shipped** | the first byte of a string open/close arrives ~1.8 ms sooner (below). Settled frames are byte for byte the plain stream |
| Per-key specialisation via `mutate:rebind` | rejected, measured | one rebind (12–18 ms) costs 3–10× a whole key (2–5 ms), and workspace code runs at file speed, so there is nothing to win back |
| Run the pad inside the workspace (so the engine tracks its AST) | rejected (not run end to end) | `set-code` replaces the workspace and can leave earlier file closures invalid; a top-level error re-runs earlier forms ([aura#4355](https://github.com/cybrid-systems/aura/issues/4355)). Dirty-node tracking covers the workspace AST (the kid's notebook, M9/M10), not the pad's buffer and caches |
| Fiber-hidden settle, committed through a generation check | rejected, unsafe | aura#4356: a thread fiber racing `read-line` corrupts the heap. Under serve-async the fiber would be cooperative, but then it runs on the same core between keys, which is what the early frame already does inline |
| Engine-dirty-driven redisplay | already used where it applies | M10 checks `query:dirty-nodes` rows ⊆ Soft DIRTY ∪ cursor for notebook mutations. Per-key buffer edits are Soft data, not AST mutations. Routing every key through `mutate:*` would cost 12+ ms each |
| Hot-strategy swap / KEEP-DROP race of two render strategies | not shipped, but possible | the machinery exists (M8/M9 worldline KEEP/DROP, `ast:snapshot`, `std/hot-strategy`). The only strategy knob with a measurable effect here, early frame on/off, is not a trade-off to race: first byte is always earlier and settle costs only +0.1–0.5 ms. So racing would just pick "on". Racing tokenizer variants live needs those variants in the workspace (12+ ms per swap), so it would run between sessions, not per key |

### What the early frame does

`soft/pad/play_in.aura` (`*pi-defer*`, set from `PAD_DEFER=1` in
`play.aura`). When a typed `"` or a backspace changes the start state
of the rows below (a string opened or closed), play-step! has already
re-lexed row l. It writes that frame at once, with row l exact, the
rows below as cached, and `DIRTY lines=l`. Then it runs the settle
(`pad:lc-line!`'s row walk) and writes the exact frame. That frame is
byte for byte the one written without deferral, because its DIRTY set
relative to the early frame is the same set (changed rows + cursor
row). The early frame is skipped when the name under the cursor
changes, because a new name re-marks other rows. It runs on the main
thread (aura#4356). C is unchanged: `pad_play` already blits any frame
as soon as it arrives.

Checks (`smoke_aura_perf.sh` → `PAD_AURA_PERF_OK`):
- `aura_perf_test.aura`, 260 quote-heavy keys, 21 early frames:
  - AP_EARLY_FRAMES: the stream minus its early frames == the plain stream.
  - AP_EARLY_ROWS: every early frame equals the frame before it with
    only row l replaced, and that row already equals row l of the
    exact frame.
- DEFER_STREAM_OK: play.aura with `PAD_DEFER=1` on a random batched
  stream gives the same frames as `PAD_DEFER` unset (minus 9 early
  frames).
- TERM_MODEL_OK: the C cell diff over the deferred stream equals a full
  repaint after every frame.

### Why this is (and is not) Aura-unique, honestly

The early frame is the jit-lock-defer idea. Emacs does it, and a C or
Rust editor can show the edited line first and fix the rows below
later. **It is not something only Aura can do.** What the Aura/Soft
setup adds:

- the settled frame is *proven* equal to the non-deferred reference on
  every smoke run, because the whole editor is a pure Soft function
  over data;
- C needed no change; the protocol already allowed extra frames.

The parts of Aura that no native editor has are the live AST surfaces:
- `mutate:rebind` + `ast:snapshot/restore`: hot swap with rollback;
- `query:dirty-nodes`: which nodes a mutation touched;
- worldline KEEP/DROP.

The pad uses these for the kid's program (M8–M10: pen KEEP/DROP, who
wrote this, dirty cross-check). On this tip they are **semantic tools,
not speed tools**. A rebind costs more than a whole key, and workspace
code runs at file speed. Claiming per-key speedups from them would be
false. A C/Rust editor *could* hot-swap a highlighter too (dlopen, a
plugin VM). What it does not get for free is engine-checked rollback
and AST dirty sets for the user's own code. That is where Aura
differs, not in keystroke latency.

## 3. Measured: pty bench (`out/bench/editors_aura.txt`)

Same harness as [`perf-emacs.md`](perf-emacs.md): same box and
container, same twelve-row file, cursor at the end of row 6, two runs.
`first` = first byte after the key, `done` = last byte before 60 ms of
quiet. The string rows now have 12 samples each (they had 5). Before =
`out/bench/editors_gap.txt` (tree `93dfd3c`/`4075523`, before gap2).

| ms per key | pad before (done) | pad now (done) | pad `PAD_DEFER=1` first / done | vim | emacs -nw |
|---|---|---|---|---|---|
| insert | 4.6 / 4.5 | **4.0 / 4.1** | 3.9 / 4.0 (no early frame) | 0.39 / 0.35 | 0.69 / 0.71 |
| cursor | 1.8 / 1.9 | **1.75 / 1.83** | 1.81 / 1.78 | 0.31 / 0.23 | 0.67 / 0.66 |
| string open (`"`) | 7.2 / 7.3 | **5.5 / 5.5** | **3.8 / 3.5** first, 5.7 / 5.5 done | 0.33 / 0.45 | 1.06 / 0.89 |
| string close (backspace) | 6.6 / 6.4 | **5.8 / 5.4** | **4.0 / 4.1** first, 6.1 / 5.9 done | 0.33 / 0.32 | 0.62 / 0.50 |

- gap2 (the row splice and the O(1) tail memo, `a147be2` / `65b4741`)
  took string open from 7.2–7.3 to 5.5 ms and insert from 4.5–4.6 to
  4.0–4.1 ms.
- The early frame takes the first byte of a string open from 5.5 to
  3.5–3.8 ms and of a close from 5.4–5.8 to 4.0–4.1 ms. Settle moves by
  +0.0–0.5 ms, the cost of the extra frame string and its write.
- vim and Emacs are still 3–17× faster on every row (cursor vs Emacs 2.7×, string open vs vim 17×). The early frame
  narrows the string rows; it does not close the gap.

## Issues filed this round

- [aura#4355](https://github.com/cybrid-systems/aura/issues/4355): a
  top-level unbound-variable error re-runs earlier forms, and closures
  can be invalid after `set-code` (repro `out/aura-perf/bug1/`).
- [aura#4356](https://github.com/cybrid-systems/aura/issues/4356): on
  the CLI, a thread fiber that allocates strings while main is in
  `read-line` corrupts strings or SIGSEGVs (the main thread skips the
  fiber body mutex).
