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

### Aura-native path behind capability detection (aura#4357, #4358, #4356)

The three Aura capabilities this round asked for are filed:

- [aura#4357](https://github.com/cybrid-systems/aura/issues/4357):
  a relower that really specialises, plus a sub-ms `mutate:rebind`. On
  `c69e644` the strategy is `:none`, 3000 calls take 258 ms from a file
  and 230 ms from the workspace, and a rebind costs 14–19 ms.
- [aura#4358](https://github.com/cybrid-systems/aura/issues/4358):
  non-blocking stdin / idle scheduling. There is no poll primitive,
  `fiber:yield` takes 0 ms (it is a no-op outside serve-async), and
  `eval:async` runs inline (199 vs 210 ms).
- [comment on aura#4356](https://github.com/cybrid-systems/aura/issues/4356#issuecomment-6013301394):
  the requirement (settle on a fiber while main waits for the next
  key), plus a proposal for a fiber-safe hand-back channel. Today
  `channel:send`/`try-recv` touch the string heap unlocked on both ends.

What the pad already does about them (`e707c35`):

| capability | probe at startup | when present | today on `c69e644` |
|---|---|---|---|
| stdin poll (#4358) | `primitive:describe "char-ready?"` returns a non-empty description (an unknown name gives `()`, so the probe is safe) | the early frame turns on by default (`PAD_DEFER=0` turns it off). When a key is already waiting, the early frame is the key's only frame and the settle is skipped: the cached rows take the early frame's rows and `*lc-L*` stays behind, so the next key goes through `play-cmd!` + `play-snap`, which re-matches every row against what the screen shows | absent, so the path stays off |
| specialising relower (#4357) | `compile:relower-strategy` needs a workspace, and `set-code` inside the pad file is unsafe (#4355). So it is probed only in `aura_facts.aura` (`cap_relower=`) | reported. Nothing switches on by itself, because the pad would first have to move into the workspace | `none` |
| fiber-safe heap / channel (#4356) | none. Running the race to find out can corrupt the heap or crash | stays off; this needs a deliberate change once Aura documents the guarantee | off |

The skip path is tested now, without the primitive.
`PAD_TEST_PENDING=k` makes every k-th early frame see a fake waiting
key.
- `AP_POLL_SKIP` (`aura_perf_test.aura`): 262 keys, 10 skips; after
  every key whose settle ran, the cached body equals a whole-page
  render.
- `POLL_SKIP_OK` (`smoke_aura_perf.sh`): play.aura on the random
  stream writes 252 frames, against 248 plain and 257 deferred. The C
  cell diff equals a full repaint after every frame (TERM_MODEL_OK),
  and the last frame's rows equal the plain path's rows.

So both paths end on identical frames. The poll path writes fewer
frames, and it never leaves a stale row on screen once the queued key
is handled.

### Where an insert's ~3 ms go (in-process profile)

These numbers come from instrumenting a copy of `play_in.aura`
(`out/aura-perf2/`, not committed). The key is typed at row 6, col 9 of
the twelve-row page, as in the pty bench. Each figure is the mean per
key over 100 insert + backspace pairs, summed from the millisecond
timer:

| section of `pad:play-step!` | µs per key |
|---|---|
| dispatch (parse the line, keymap memo, cursor/name checks) | 385 |
| new row and lines lists, undo entry | 340 |
| re-lex from the first changed token (`pad:lc-scan`) | 1295 |
| keep check (end state + def-carry vs row l+1) | 290 |
| row strings, `*lc-recv*` / `*lc-rowv*` splice | 285 |
| commit (`set!` of the caches) | 205 |
| frame string | 185 |
| write | 45 |

The in-process total is 2.9–3.2 ms per key. The pty bench adds about
1 ms for C, the pipe and the pty. The costs are spread over about 150
Soft operations and 2–3 closure calls. A Soft closure call costs
0.30–0.36 ms however small or large its body (`fsmall` vs `fbig`
probe), so `pad:lc-scan` is about a quarter call and three quarters
scan steps and token/tape building. There is no single allocation to
cut. Measured negatives:

- **Native `take` instead of `(reverse (drop (reverse x) k))`** for
  the six list prefixes on the key path is *slower*: 4.0–4.4 instead
  of 2.9–3.1 ms per key in-process. Not shipped.
- The cost of `list` / `reverse` / `append` does not grow with heap
  size (0.15 ms per call from a small heap up to +3M live pairs).
- Deep `let*` chains, many locals and global reads cost nothing
  measurable next to a call.

To go further the pad needs cheaper Soft calls
([aura#4350](https://github.com/cybrid-systems/aura/issues/4350)) or a
relower that specialises the key path
([aura#4357](https://github.com/cybrid-systems/aura/issues/4357)).
Without them the remaining choice was to inline `pad:lc-scan`'s common
case (an edit at the end of a row) into `play-step!`. That was done
later (`0499ae0`, below). It saves 0.5–0.6 ms per insert in process,
and `GAP3_EOL_ENTRY` checks that the duplicated tokenizer logic matches
a full scan.

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

### Re-run at `e707c35` (capability round, `out/bench/editors_aura2.txt`)

Same harness, two runs, measured 17:49–18:20 (UTC+8). The box was
shared: other agents' `aura --serve-async` and `aura_build` jobs were
running, with load average 1.1–1.6 on 8 cores. They were left alone.
Run 2 is slower for every editor, vim and Emacs included.

| ms per key (run 1 / run 2) | pad | pad `PAD_DEFER=1` first / done | vim | emacs -nw |
|---|---|---|---|---|
| insert | 3.9 / 4.0 | 3.8 / 4.1 | 0.32 / 0.42 | 0.66 / 0.78 |
| cursor | 1.79 / 1.91 | 1.75 / 1.87 | 0.25 / 0.25 | 0.64 / 0.80 |
| string open (`"`) | 5.5 / 5.8 | **3.8 / 4.2** first, 5.8 / 6.5 done | 0.47 / 0.83 | 0.91 / 1.09 |
| string close (backspace) | 5.6 / 5.7 | **4.4 / 4.0** first, 6.2 / 6.0 done | 0.51 / 0.48 | 0.53 / 0.72 |

This matches the earlier table within noise, which is expected: the
capability round changed no step on the default key path, because with
no poll primitive the settle-skip branch never runs. Insert stays at
4 ms, 9–12× vim and 5–6× Emacs. Per the profile above, nothing on the
pad side cuts that by a large factor before #4350 / #4357 land.

### Re-run at `0499ae0` (end-of-row shave, `out/bench/editors_aura3.txt`)

End-of-row edits skip `pad:lc-scan` (the "remaining choice" named in
the profile above, now done, with a field-by-field check against a
full scan in `GAP3_EOL_ENTRY`). In process, insert went from 2.9–3.1 to
2.3–2.6 ms per key. Two pty runs were measured 18:40–19:12 (UTC+8).
Load average was 2.0–2.9, because other agents' jobs were running and
the M11 probes ran during run 2.

| ms per key (run 1 / run 2) | pad | pad `PAD_DEFER=1` first / done | vim | emacs -nw |
|---|---|---|---|---|
| insert | **3.8 / 3.3** | 3.1 / 3.2 | 0.41 / 0.46 | 0.66 / 0.67 |
| cursor | 1.86 / 1.74 | 1.76 / 1.78 | 0.25 / 0.31 | 0.67 / 0.67 |
| string open (`"`) | 6.4 / 5.8 | 4.0 / 4.2 first, 6.1 / 5.9 done | 0.78 / 0.45 | 1.01 / 1.09 |
| string close (backspace) | 5.9 / 5.5 | 4.0 / 3.8 first, 6.2 / 5.8 done | 0.59 / 0.53 | 0.57 / 0.76 |

Insert is now 3.1–3.8 ms, down from 3.9–4.1. String keys are unchanged,
because the quote still goes through the scan, and their run-to-run
noise is about ±0.5 ms. Insert is still about 7–9× slower than vim and
about 5× slower than Emacs.

## Issues filed this round

- [aura#4355](https://github.com/cybrid-systems/aura/issues/4355): a
  top-level unbound-variable error re-runs earlier forms, and closures
  can be invalid after `set-code` (repro `out/aura-perf/bug1/`).
- [aura#4356](https://github.com/cybrid-systems/aura/issues/4356): on
  the CLI, a thread fiber that allocates strings while main is in
  `read-line` corrupts strings or SIGSEGVs (the main thread skips the
  fiber body mutex). Capability comment (hand-back channel proposal):
  [#4356 comment](https://github.com/cybrid-systems/aura/issues/4356#issuecomment-6013301394).
- [aura#4357](https://github.com/cybrid-systems/aura/issues/4357):
  relower strategy `:none`, workspace runs at file speed, `mutate:rebind`
  14–19 ms (repro inline in the issue).
- [aura#4358](https://github.com/cybrid-systems/aura/issues/4358): no
  non-blocking stdin poll / idle scheduling in Soft (repro inline
  in the issue).
- [aura#4362](https://github.com/cybrid-systems/aura/issues/4362)
  (M11 round, [`m11.md`](m11.md)): `mutate:atomic-batch` skips the
  post-mutate type/arity gate.
