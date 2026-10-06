#!/usr/bin/env bash
# Full stack: M0 race → M1 hot swap/heal → M2 fixture propose → optional
# live MiniMax propose (PAD_M2_PROPOSE_LIVE_SKIP when no key, or PAD_LIVE=0)
# → fixture burn → M3 multi-line buffer + command-helper propose (fixtures,
# then optional live helper; PAD_M3_LIVE_SKIP when no key or PAD_LIVE=0)
# → M3.5 finer editor (paren check, Python model, Soft unit tests
# PAD_TEST_OK, goal3 helper race + world undo PAD_M35_OK, optional live
# --helper3; PAD_M35_LIVE_SKIP when no key or PAD_LIVE=0)
# → M4 two pads + find/replace + record/play (paren, Python model
# PAD_M4_MODEL_OK, Soft tests PAD_M4_TEST_OK, law race + macro race +
# macro undo PAD_M4_OK, optional live --macro; PAD_M4_LIVE_SKIP when no key
# or PAD_LIVE=0).
# → M5 Soft Aura HL + LSP-lite jump/refs + Soft query/mutate bridge
# (paren, Python model PAD_M5_MODEL_OK, Soft tests PAD_M5_TEST_OK,
# HL/jump/query smoke PAD_M5_OK).
# → M6 thin C viewport (Soft tests PAD_M6_TEST_OK, Soft snapshot PAD_M6_OK,
# host model PAD_M6_MODEL_OK, C thin guard, golden/fail-closed blits,
# soft_play → C blit; PAD_C_OK). Soft owns the editor; C only blits.
# → M7 snappy pad: line-incremental Soft key path (Soft tests
# PAD_M7_TEST_OK, DIRTY audit PAD_M7_DIRTY_OK, key-path latency
# PAD_PERF_OK + PAD_M7_PERF_OK; PAD_M7_OK). C unchanged.
# → M8 kid onboarding card + intent worldline (welcome CARD,
# goal: command, pd:goal race, gate/capability, undo KEEP;
# PAD_M8_OK). Soft owns cards; C unchanged.
# → M9 workspace notebook + pen (ctrl-s = set-code + eval-current, engine
# names vs Soft names, define-lookup marks, pen KEEP/DROP/REJECT with
# ast:snapshot heal, zero set-code between checks; M9_ACC 1..6 OK,
# PAD_M9_OK). Soft owns the notebook; C unchanged.
# → M10 who wrote this (ctrl-o row stamps kid/helper/macro/law, pen
# undo = ast:restore + re-project agree, engine query:dirty-nodes rows ⊆
# Soft DIRTY ∪ cursor; M10_ACC 1..4 OK, PAD_M10_OK). C unchanged.
# → M11 Aura-unique features: an AI proposal is one typed engine
# transaction (typed-mutate-atomic, AURA_MUTATE_TYPE_GATE=hard), ctrl-z
# undoes it whole (PAD_M11_UNDO_OK); ctrl-o answers from engine node
# provenance under agent fingerprints, cross-checked with the Soft stamps
# (PAD_M11_WHO_OK); a refused proposal is explained in kid words from
# aura's own reason (PAD_M11_WHY_OK); a blast radius card lists what a
# proposal would move before KEEP (PAD_M11_BLAST_OK); a time machine
# steps through every KEEP's snapshot and a saved book reopens with its
# story via serialize/deserialize-workspace (PAD_M11_TIME_OK); AI ideas
# race in sandbox child worlds and only a winner comes back by rebind
# (PAD_M11_WORLD_OK); the kid changes editor rules (tab size, say
# length) live through a gated typed write that ctrl-z and the time
# machine undo (PAD_M11_RULES_OK); the helper repairs its own idea with
# intend, verified in child worlds, timeline from intend-history
# (PAD_M11_FIX_OK). C unchanged.
# → M12 the book closes: std/persist unbound → GAPS persist; Soft
# snapshot via serialize-workspace + .pad sidecar; open is restore
# (deserialize-workspace, no set-code guess); who still answers
# (PAD_M12_OK). Play loop does not load book.aura. C unchanged.
# → M13 aura notebook pad: sexp projection, M5 HL tape, Soft jump +
# workspace defines, GAPS hygienic-play when clone_macro_body unbound,
# fixture race DROP (PAD_M13_OK). Play loop does not load aura_pad.aura.
# C unchanged.
# → gap round: one Soft entry per key (play_in.aura), flat line scanner,
# C cell-diff tty update with IL/DL (Soft tests PAD_GAP_TEST_OK, batched
# lines == byte lines, term model TERM_MODEL_OK; PAD_GAP_OK).
# → aura-perf round: PAD_DEFER early frame for string edits (settled
# stream == plain stream, early rows exact), Aura surface facts
# (rebind / snapshot / fiber / relower), tty model (PAD_AURA_PERF_OK).
# Ends with PAD_SMOKE_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"

bash "$ROOT/scripts/smoke_soft.sh"
bash "$ROOT/scripts/smoke_m1.sh"
bash "$ROOT/scripts/smoke_m2.sh"

if [[ "${PAD_LIVE:-1}" != "1" ]]; then
  echo "PAD_M2_PROPOSE_LIVE_SKIP reason=PAD_LIVE=0"
elif ! python3 "$ROOT/scripts/propose_minimax.py" --check 2>/dev/null; then
  echo "PAD_M2_PROPOSE_LIVE_SKIP reason=no-key"
else
  echo "smoke: live MiniMax propose"
  live="$ROOT/out/live_pack.lambda"
  rm -f "$live"
  if python3 "$ROOT/scripts/propose_minimax.py" "$live" 1 "smoke" \
      >/dev/null 2>"$ROOT/out/live_propose.stderr"; then
    cat "$ROOT/out/live_propose.stderr" >&2 || true
    test -s "$live"
    echo "LIVE_LAMBDA $(head -c 200 "$live" | tr -d '\n')"
    PAD_PROPOSE_FILE="/workspace/aura-pad/out/live_pack.lambda" \
      bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m2_live.aura \
      >"$ROOT/out/m2_live.txt" 2>"$ROOT/out/m2_live.err"
    cat "$ROOT/out/m2_live.txt"
    if [[ -s "$ROOT/out/m2_live.err" ]]; then
      cat "$ROOT/out/m2_live.err" >&2
    fi
    if ! grep -q 'PAD_M2_PROPOSE_LIVE_OK' "$ROOT/out/m2_live.txt" \
       || grep -qiE 'error:|unbound variable' "$ROOT/out/m2_live.txt" "$ROOT/out/m2_live.err"; then
      echo "PAD_M2_PROPOSE_LIVE_FAIL" >&2
      exit 1
    fi
    echo "PAD_M2_PROPOSE_LIVE_OK"
  else
    cat "$ROOT/out/live_propose.stderr" >&2 || true
    echo "PAD_M2_PROPOSE_LIVE_FAIL (host propose)" >&2
    exit 1
  fi
fi

echo "smoke: fixture burn"
PAD_PROPOSE=0 bash "$ROOT/scripts/burn.sh"

echo "smoke: m3 multi-line + command helper"
bash "$ROOT/scripts/smoke_m3.sh"

echo "smoke: m3.5 finer editor + tests"
bash "$ROOT/scripts/smoke_m35.sh"

echo "smoke: m4 pads + find/replace + macros"
bash "$ROOT/scripts/smoke_m4.sh"

echo "smoke: m5 HL + jump/refs + query/mutate"
bash "$ROOT/scripts/smoke_m5.sh"

echo "smoke: m6 thin C viewport (Soft dump -> C blit)"
bash "$ROOT/scripts/smoke_c.sh"

echo "smoke: m7 snappy pad (line-incremental Soft key path + perf)"
bash "$ROOT/scripts/smoke_m7.sh"

echo "smoke: m8 kid card + intent worldline"
bash "$ROOT/scripts/smoke_m8.sh"

echo "smoke: m9 workspace notebook + pen"
bash "$ROOT/scripts/smoke_m9.sh"

echo "smoke: m10 who wrote this + engine dirty"
bash "$ROOT/scripts/smoke_m10.sh"

echo "smoke: m11 Aura-unique features (robot txn undo, engine who, kid why, blast card, time machine, sandbox worlds, kid rules, intend repair)"
bash "$ROOT/scripts/smoke_m11.sh"
echo "smoke: m12 the book closes (persist probe + open-is-restore)"
bash "$ROOT/scripts/smoke_m12.sh"
echo "smoke: m13 aura notebook (sexp pad, hygienic GAPS, fixture race)"
bash "$ROOT/scripts/smoke_m13.sh"

echo "smoke: gap round (one Soft entry per key + C cell-diff tty update)"
bash "$ROOT/scripts/smoke_gap.sh"

echo "smoke: aura-perf round (early frame + Aura surface facts)"
bash "$ROOT/scripts/smoke_aura_perf.sh"

echo "smoke: PAD_SMOKE_OK"
