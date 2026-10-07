# aura-pad issues

Live plan: [`ROADMAP.md`](ROADMAP.md). Design: [`DESIGN.md`](DESIGN.md).
M0–M13 stay green: the full `PAD_LIVE=0 bash scripts/smoke.sh` ends
`PAD_SMOKE_OK` on `18b48dc` with the hard type gate (2026-10-07 14:20 CST).

Soft binary: **`18b48dc`** (aura main 2026-10-07 before the #4350 capture
snapshots), built in `ghcr.io/cybrid-systems/dev:v1.0.9`. Latest main
`0ba8690` (and `e7b236d`) is **not usable**: R4 below hangs the pad. Every
aura-pad issue #4343–#4370 was re-run on `18b48dc` (repros in
`out/newaura/repro/`); the repro is trusted over the closed label. Pad
work never invents a replacement API.

### Fixed on `18b48dc`: workaround removed, native path used

| Aura issue | Was | Pad now |
|------------|-----|---------|
| [aura#4370](https://github.com/cybrid-systems/aura/issues/4370) | `intend` aliased kept strings | `fix_loop.aura` keeps the strings `intend` hands over, no `string-append` copies |
| [aura#4369](https://github.com/cybrid-systems/aura/issues/4369) / [aura#4368](https://github.com/cybrid-systems/aura/issues/4368) | child rebind leaked into root; `workspace:delete` crashed | M11f: `workspace :switch 0` + `workspace:conflicts-with` + `workspace:delete` per idea; no root heal, no child left (`F2_WORLD_DELETED`, `F2_NO_TRY_LISTED`) |
| [aura#4367](https://github.com/cybrid-systems/aura/issues/4367) / [aura#4365](https://github.com/cybrid-systems/aura/issues/4365) | reopened log lost authors, node ids not remapped | M11e ctrl-o after an open asks the engine's node provenance (`pad:time-eng-of`); the stamp/`sum=` join is gone (`E3_LOG_KEPT_AUTHORS`, `E3_WHO0_NATIVE`) |
| [aura#4364](https://github.com/cybrid-systems/aura/issues/4364) | `query:calls` only grew | M11d blast card checks the engine total equals Soft's call sites (`hello:3/3`), no before/after delta |
| [aura#4363](https://github.com/cybrid-systems/aura/issues/4363) | false `unbound variable` for value defines | `why.aura` keeps every diagnostic (no filter); C3 asserts no false `pet` |
| [aura#4358](https://github.com/cybrid-systems/aura/issues/4358) | no stdin poll | `char-ready?` (b8f008d) called directly in `play.aura`: early frame + settle skip on by default |
| [aura#4347](https://github.com/cybrid-systems/aura/issues/4347) | `define-lookup` line/col 0 | engine records now land (`((7 3 2))`); jump uses them, marks stay Soft-owned |
| [aura#4351](https://github.com/cybrid-systems/aura/issues/4351), [aura#4352](https://github.com/cybrid-systems/aura/issues/4352), [aura#4353](https://github.com/cybrid-systems/aura/issues/4353), [aura#4354](https://github.com/cybrid-systems/aura/issues/4354), [aura#4355](https://github.com/cybrid-systems/aura/issues/4355), [aura#4356](https://github.com/cybrid-systems/aura/issues/4356), [aura#4359](https://github.com/cybrid-systems/aura/issues/4359), [aura#4361](https://github.com/cybrid-systems/aura/issues/4361), [aura#4366](https://github.com/cybrid-systems/aura/issues/4366) | see history | repros pass. The coding rules they caused (std first, no top-level named let, loop data as parameters, new names for wrappers, trailing `#t`) are kept: harmless and still needed on `c69e644` |
| [aura#4362](https://github.com/cybrid-systems/aura/issues/4362) | `mutate:atomic-batch` skipped the gate | batch gates now, but it is marked deprecated; proposals stay on `typed-mutate-atomic` under `AURA_MUTATE_TYPE_GATE=hard` (see R3) |
| [aura#4357](https://github.com/cybrid-systems/aura/issues/4357) | no relower | the repro is fixed (incremental, 227→2 ms). At pad scale no gain: specialisation capped at 8 lambdas, a hot rebind is `full` 0.3–1.2 s and re-runs top-level forms ([comment](https://github.com/cybrid-systems/aura/issues/4357#issuecomment-6031224592)). The pad keeps its file-mode key path |
| [aura#4356](https://github.com/cybrid-systems/aura/issues/4356) | fibers raced `read-line` | race fixed (0 bad ×3). A fiber spawned before `read-line` does not run during the wait (`out/newaura/fib/`), so the early frame stays on the main thread |
| [aura#4349](https://github.com/cybrid-systems/aura/issues/4349) | stale ids after restore | the error is catchable now; restore + one `eval-current` is still the documented heal |

### Still broken or regressed on `18b48dc` (pad workaround kept)

| Issue | What is wrong | Pad rule |
|-------|---------------|----------|
| [aura#4350](https://github.com/cybrid-systems/aura/issues/4350) (open) | call cost still linear in define count: 2000 calls 182/466/1186 ms at N=0/300/1000 (`c69e644` 168/437/1058). `e7b236d` fixes it (18/22/30) but brings R4 ([comment](https://github.com/cybrid-systems/aura/issues/4350#issuecomment-6031223604)) | inlined hot paths, no inner named let on the key path, one `set-code` per check |
| [aura#4343](https://github.com/cybrid-systems/aura/issues/4343) | spin 10000: 1642/3573/9658 ms at N=0/200/800 (only `e7b236d`: 101/131/204) | as #4350 |
| R1 on [aura#4346](https://github.com/cybrid-systems/aura/issues/4346) | `vector-set!` / `set-car!` ~10× slower with defines: 440→4266 ms per 200 at N=600 ([comment](https://github.com/cybrid-systems/aura/issues/4346#issuecomment-6031218868)) | `list->vector`, no in-place mutation on the key path |
| R2 on [aura#4360](https://github.com/cybrid-systems/aura/issues/4360) | after an add-path `mutate:rebind`, existing closures raise `invalid closure` until `eval-current` ([comment](https://github.com/cybrid-systems/aura/issues/4360#issuecomment-6031220092)) | one `eval-current` after any add |
| R3 on [aura#4362](https://github.com/cybrid-systems/aura/issues/4362) | soft gate (default) now commits caller arity mismatches for `mutate:rebind` and `typed-mutate-atomic`; hard still refuses ([comment](https://github.com/cybrid-systems/aura/issues/4362#issuecomment-6031221755)) | `scripts/run_soft.sh` defaults to `AURA_MUTATE_TYPE_GATE=hard`: soft also commits unbound-variable rebinds ([follow-up](https://github.com/cybrid-systems/aura/issues/4362#issuecomment-6031717769)) |
| R5 on [aura#4349](https://github.com/cybrid-systems/aura/issues/4349) | a plain `ast:snapshot` makes every workspace closure `invalid closure`; `eval-current` alone does not rebind (`out/newaura/repro/snap_inv.aura`) ([comment](https://github.com/cybrid-systems/aura/issues/4349#issuecomment-6031254254)) | `pad:time-snap` (time machine) and `pad:hs-register!` (std/hot-strategy register!, M1–M4 / M8): restore of the new snapshot + one `eval-current`. In the time machine the generations this costs go to `*pen-gen-skew*`, so a KEEP still moves the pad generation by one |
| R6 on [aura#4357](https://github.com/cybrid-systems/aura/issues/4357) | booleans in workspace code (`set-code` + `eval-current`) evaluate to `1` / `0` (`out/newaura/repro/bool_ws.aura`; suspect d431ffb) ([comment](https://github.com/cybrid-systems/aura/issues/4357#issuecomment-6031716810)) | `pad:plan-check-body` (`lines.aura`): the engine probe value is checked, then the same body run by Soft eval (helper / macro / goal probes); the M3.5 / M4 `FX_UGLY` unit checks test the Soft-built list |
| R4 (filed by user form (pending)) | since `e7b236d` (#4350 capture snapshots): `set!` on a captured local is lost or `unbound variable: set!: i`; std `string-trim` and the pad m3 smoke hang (`out/newaura/repro/setcap.aura`, `trim_nr.aura`; body `out/newaura/issue_R4.md`). | stay on `18b48dc` |
| R7 on [aura#4360](https://github.com/cybrid-systems/aura/issues/4360) | under the hard gate a plain `mutate:rebind` of an existing name leaves its callers with `invalid closure` (soft: after an `ast:snapshot`). An uncaught `invalid closure` re-runs the entry file from scratch (side effects twice), then is fatal; `c69e644` is fine (`out/newaura/repro/rerun.aura`, `rerun2.aura`) ([comment](https://github.com/cybrid-systems/aura/issues/4360#issuecomment-6032046053)) | one `eval-current` after each rebind in `aura_facts.aura` (the smokes caught it there) |

Gaps seen on `18b48dc`: `query:find-by-name` and `clone_macro_body` unbound;
`std/persist` loads with `(require "std/persist" all:)`.

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

## M11a–h — Aura-unique features (done)

[`m11.md`](m11.md), from the ranked list in [`aura-vs-rust.md`](aura-vs-rust.md).
M11a "undo the robot" is done (`PAD_M11_UNDO_OK`): one AI proposal is one
`typed-mutate-atomic` transaction, and ctrl-z undoes it whole. Filed #4362.
M11b engine "who wrote this" is done (`PAD_M11_WHO_OK`): agent fingerprints
plus `query:node-provenance` answer ctrl-o and agree with the Soft stamps.
M11c "why did it break" is done (`PAD_M11_WHY_OK`): a refused proposal is
replayed per edit and aura's reason becomes one kid sentence. Filed #4363.
M11d "blast radius" is done (`PAD_M11_BLAST_OK`): the card lists the places
a proposal would move before KEEP, checked against `query:calls` and dirty
defines (engine call count stale after rebind, filed #4364).
M11e time machine + open-is-restore is done (`PAD_M11_TIME_OK`): every
KEEP is a step on a strip (ctrl-t / ctrl-n), checked with `ast:diff`; a
book saves with `serialize-workspace` and reopens with its story and who
(#4365 workaround; filed #4366, #4367).
M11f sandbox worlds is done (`PAD_M11_WORLD_OK`): each AI idea is tried in
its own child world (`workspace :create` / `:switch`), scored on the kid's
goal there, and only an idea that beats the page comes back, by rebind
(filed #4368: root bindings stay the child's until `ast:restore`). The
children stay listed: `workspace:discard` only resets a child (documented),
and `workspace:delete` after a leaked rebind crashes (filed #4369).
M11g the kid changes editor rules live is done (`PAD_M11_RULES_OK`): rules
are page defines (`(tab-size)`, `(say-max)`); "tab 4" passes a Soft rule
gate with kid words, is one `typed-mutate-atomic` under fingerprint kid=1,
lands as a robot KEEP (ctrl-z, who stamps, time-machine step) and is
verified by calling the live rule (a helper's out-of-range body is undone
at once).
M11h the helper repairs its own idea is done (`PAD_M11_FIX_OK`): Soft
calls `(intend goal gen verify fix max)`; the Soft verifier tries each
idea in a child world (never evals generated code, aura#4359) and answers
in kid words; Soft copies intend code/err with `string-append` before the
next try (filed #4370); a passing idea is one robot KEEP.

## Wire v2 — skip SNAP rows C has (done, no gain)

Soft tip `c69e644`. Marker `PAD_WIRE2_OK`. See [`perf.md`](perf.md),
"wire v2", and DESIGN §7.1. v1 stays the default.

- No new Soft bug found. Nothing to file.
- The cost that ate the gain is the known per-call floor: one
  named-let step calling an empty `(lambda () 0)` (two Soft calls) costs
  ~0.26 ms in the play-path define set (#4350, still open). Do not re-file it; add the number to #4350 when
  cursor-github auth is back (**to add as a comment, not a new issue**).
- Probed: no string hash builtin on this tip (`string-hash`, `crc32`,
  `sha256`, `fnv1a` are unbound; `hash` makes a table). v2 uses a
  generation number plus the body length instead. This is a gap, not a
  bug, so there is nothing to file.

## M13 — aura notebook (done)

Was the NEXT.md "M11 — aura notebook" sketch; M11 shipped as Aura-unique
features. Soft tip `c69e644`. Marker `PAD_M13_OK`. [`m13.md`](m13.md).

- M13.1 Third pad `aura`: sexp projection, M5 HL tape (`P K S T C Q M N`).
- M13.2 Jump: Soft HL goto-def; workspace load consults `define-lookup`
  (`query:find-by-name` unbound on tip — not called; #4347 line/col 0).
- M13.3 Hygienic macro play: `clone_macro_body` unbound → `GAPS hygienic-play`,
  refuse to mutate. Do not re-file #165.
- M13.4 Fixture race: helper that fails `(hello 3)=>4` DROPs.

## M12 — the book closes (done)

[`m12.md`](m12.md). Soft tip `c69e644`.

- M12.1 `std/persist` unbound → `GAPS persist`. Soft snapshot =
  `serialize-workspace` (`.aw`) + `.pad` sidecar (`book.aura`). No new
  Aura issue: missing `std/persist` is the expected GAP on this tip.
- M12.2 Open is `deserialize-workspace` + sidecar restore. `who` still
  answers (#4365/#4367). → `PAD_M12_OK`.
