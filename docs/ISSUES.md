# aura-pad issues

Live plan: [`ROADMAP.md`](ROADMAP.md). Design: [`DESIGN.md`](DESIGN.md).
M0–M10 stay green.

Soft tip: `c69e644`. Aura issues filed from aura-pad. Pad work never
invents a replacement API for any of them.

### Open

| Aura issue | What is wrong | Pad rule until it lands |
|------------|---------------|-------------------------|
| [aura#4362](https://github.com/cybrid-systems/aura/issues/4362) | `mutate:atomic-batch` skips the post-mutate type/arity gate in both gate modes: a batch commits a rebind that `mutate:rebind` refuses. `typed-mutate-atomic` gates, but returns only `#t`/`#f` | AI proposals go through `typed-mutate-atomic` (`robot.aura`, M11a) under `AURA_MUTATE_TYPE_GATE=hard`; never `mutate:atomic-batch` for kid code |
| [aura#4358](https://github.com/cybrid-systems/aura/issues/4358) | No non-blocking stdin poll in Soft (`char-ready?` or similar); `fiber:yield` is a no-op outside serve-async and `eval:async` runs synchronously, so the play loop cannot see that a key is waiting or do idle work between keys | Early frame stays opt-in (`PAD_DEFER=1`). `play.aura` probes `primitive:describe "char-ready?"` at startup; when it exists, the early frame turns on by default and a waiting key skips the settle (`*pi-pending*`). The skip path is tested now with a fake poll (`PAD_TEST_PENDING`, `AP_POLL_SKIP`, `POLL_SKIP_OK`) |
| [aura#4357](https://github.com/cybrid-systems/aura/issues/4357) | `compile:relower-strategy` answers `:none`; workspace code runs at file speed; one `mutate:rebind` costs 14–19 ms (more than a whole key); file mode has no workspace before `set-code` | No per-key rebind or workspace specialisation. `aura_facts.aura` reports `cap_relower` so a specialising relower shows up in the smoke output |
| [aura#4356](https://github.com/cybrid-systems/aura/issues/4356) | CLI fibers are OS threads (`fiber:spawn-backend` 2). The main thread does not take the fiber body mutex, and `read-line` pushes to the string heap unlocked, so a fiber allocating strings while main waits in `read-line` corrupts strings or SIGSEGVs | No fiber runs while the play loop is in `read-line`; the early frame and settle stay on the main thread (`perf-aura.md`) |
| [aura#4355](https://github.com/cybrid-systems/aura/issues/4355) | A top-level unbound-variable error re-runs earlier top-level forms; closures defined before a `set-code` can be invalid afterwards | Keep `set-code` out of files that hold pad closures (`aura_facts.aura` is separate); M9/M10 use it only on their notebook paths |
| [aura#4354](https://github.com/cybrid-systems/aura/issues/4354) | `(define base f)` then `(define (f x) ... (base x))` inside a LOADED file: `base` runs the new `f` (infinite loop). Inline in the main file it works | Never save-and-redefine a procedure in a loaded file; wrappers get a new name (`pad:pi-line!` in `play_in.aura`) |
| [aura#4353](https://github.com/cybrid-systems/aura/issues/4353) | An outer local (let / let* / parameter) captured inside a named-let or letrec body resolves to a same-named global (procedure or value). Silent wrong value (std/math `e`, pad globals `row`, `p1`, ...) | Do not read captured outer locals in named lets whose names exist as globals; new loops take their data as parameters; test globals carry a file prefix (`m10:`, `*m10-`) |
| [aura#4352](https://github.com/cybrid-systems/aura/issues/4352) | A top-level named let that calls a user proc, in a loaded file, breaks later prelude calls (`reverse`: unbound `lst`). In the full stack this showed up as random type errors and calls to the wrong function | No top-level named let in loaded files; build tables with a named procedure (`pad:lc-cls-list`) |
| [aura#4351](https://github.com/cybrid-systems/aura/issues/4351) | `null?` in a loaded file with `(require ... all:)` calls a pad global | Entry files load `std.aura` (the requires) before any pad file; `query.aura` has no requires |
| [aura#4350](https://github.com/cybrid-systems/aura/issues/4350) | #4343 / #4346 repros still linear in define count on `c69e644`; calls ~1.5× slower than `73c012c` | One `set-code` per check, never per key. `list->vector`, no `vector-set!`. Numbers in `perf.md` |
| [aura#4349](https://github.com/cybrid-systems/aura/issues/4349) | After `ast:restore` past a rebind, workspace closures throw "stale node id" | The pen heals with `ast:restore` + one `eval-current` (counted in `M9STATS heals=`) |
| [aura#4348](https://github.com/cybrid-systems/aura/issues/4348) | Soft file string literals lose a backslash | Notebook rows travel as char codes, never as escaped strings |
| [aura#4347](https://github.com/cybrid-systems/aura/issues/4347) | `define-lookup` line/col always 0 | Marks come from Soft tokens; engine records are used only when they land on the name; `M9LOOKUP hello=line0:col0` printed |

### Closed (re-probed on `c69e644`)

| Aura issue | Status on tip |
|------------|---------------|
| [aura#4346](https://github.com/cybrid-systems/aura/issues/4346) | `vector-set!` / `set-car!` cost. Closed, but the re-measure still scales (#4350) |
| [aura#4345](https://github.com/cybrid-systems/aura/issues/4345) | `query:code` / `query:ref-counts` / `query:node-types` bound. `USED` line |
| [aura#4344](https://github.com/cybrid-systems/aura/issues/4344) | `define-lookup` bound. Jump hook wired (see #4347) |
| [aura#4343](https://github.com/cybrid-systems/aura/issues/4343) | Closed, but per-key ms did not drop on the file runner (#4350) |

#192 and #165 are closed. Do not re-file them. Probe fail is still `ast:snapshot` / `ast:restore`.

## M7 — snappy pad (done)

Shipped as a Soft-side latency increment ([`m7.md`](m7.md)). The earlier
"workspace is the buffer" sketch is now **M9**.

- M7.1 Line cache + exact DIRTY; every frame equals the whole-page oracle (`PAD_M7_TEST_OK`).
- M7.2 DIRTY sound + tight on a Soft play stream (`PAD_M7_DIRTY_OK`); C unchanged.
- M7.3 Twelve-row insert < 50 ms and ≥ 2× vs M6; small page < 50 ms (`PAD_PERF_OK`, `PAD_M7_PERF_OK`). Soft floor published.
- M7.4 `PAD_M7_OK`. M0–M6 markers still print.

## M8 — intent worldline (done)

No new Aura issue. Uses hot-strategy + fibers already on tip.

- M8.1 `pd:goal` slot, ugly pack HEAL.
- M8.2 Two cards in SNAP SAY. C does not pick the winner.
- M8.3 Kind-word gate + capability probe. Unbound capability is a GAP, word-list stays.
- M8.4 Undo KEEP re-scores. Mismatch fails loud. Fixtures: worse DROP, tie DROP, better KEEP.

## M9 — workspace notebook (done)

Shipped ([`m9.md`](m9.md)). Filed while building it: #4347, #4348, #4349,
#4350, #4351, #4352.

- M9.1 Re-probe tip: `USED define-lookup.query:code.query:ref-counts.query:node-types`, `GAPS none`.
- M9.2 `pad:ws-load!` once per notebook / check (`set-code` + `eval-current`). Projection matches `"hi"` / `"  aura"` / `"pad"` and the 12-row page.
- M9.3 Keystrokes between checks make zero `set-code` calls. REJECT does not bump generation.
- M9.4 `PAD_M9_OK`. M0–M8 markers still print.

## M10 — who wrote this + engine dirty (done)

Shipped ([`m10.md`](m10.md)). Filed while building it: #4353.
`query:dirty-nodes` is bound on `c69e644`.

- M10.1 Stamp `who/why/gen` per row (`gen` from the engine metrics face, `pad:pen-gen`).
- M10.2 `who` command (`ctrl-o`). Pen undo = `ast:restore` + re-project, agree or fail loud. No guessed text.
- M10.3 Soft DIRTY ↔ engine dirty-nodes cross-check; nodes outside every page define print `GAPS query:node-row`.

## Gap round — pty latency (done)

The pty bench went from insert 7.9–8.2 to 4.5–4.6 ms per key and from cursor
6.8–7.0 to 1.8–1.9 ms per key. Numbers are in [`perf.md`](perf.md) and
[`perf-emacs.md`](perf-emacs.md); the gate is `PAD_GAP_OK`. The parent filed #4354 while building it. New
Soft cost numbers (named-let entry, `map integer->char`) went to #4350.

## Aura-native perf round (done)

[`perf-aura.md`](perf-aura.md): the `PAD_DEFER` early frame (string open
first byte 5.5 → 3.5–3.8 ms; settled frames byte for byte the plain
stream). Measured why rebind/relower and CLI fibers give no per-key gain.
Gate `PAD_AURA_PERF_OK`. Filed #4355, #4356.
Capability round: filed #4357 (relower/rebind) and #4358 (stdin poll),
and commented on #4356 (fiber-safe hand-back channel). The pad switches
the poll path on by itself when `char-ready?` appears.

## M11a–d — Aura-unique features (in progress)

[`m11.md`](m11.md), from the ranked list in [`aura-vs-rust.md`](aura-vs-rust.md).
M11a "undo the robot" is done (`PAD_M11_UNDO_OK`): one AI proposal is one
`typed-mutate-atomic` transaction, and ctrl-z undoes it whole. Filed #4362.

## M11 — aura notebook

Blocked on #4344 for engine goto-def, #4345 for code/refs/types, #4343 for load cost.

- M11.1 Third pad `aura`. HL tape reused. Jump does not call `define-lookup`.
- M11.2 Hygienic play: missing surface → `GAPS hygienic-play`, no mutate.
- M11.3 Fixture race. Record call cost next to #4343 numbers.

## M12 — book

- M12.1 `std/persist` probe. Unbound → `GAPS persist` + Soft snapshot file.
- M12.2 Open is restore. `who` still answers.
