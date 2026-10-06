#!/usr/bin/env bash
# M5: Soft Aura syntax highlight, LSP-lite jump/refs, Soft query/mutate bridge.
#   1. paren balance of Soft + M5 fixtures          -> PAREN_OK
#   2. host Python HL/jump model                    -> PAD_M5_MODEL_OK
#   3. Soft tests (m5_test.aura, >= 50 checks)      -> PAD_M5_TEST_OK
#   4. HL + jump + query/mutate smoke               -> PAD_M5_OK
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/out"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT"/soft/pad/*.aura \
  "$ROOT"/soft/pad/fixtures/m4/*.lambda \
  "$ROOT"/soft/pad/fixtures/m5/*.aura

python3 "$ROOT/scripts/hl_model.py" --check >"$ROOT/out/m5_model.txt"
tail -1 "$ROOT/out/m5_model.txt"
grep -q '^PAD_M5_MODEL_OK$' "$ROOT/out/m5_model.txt" || { cat "$ROOT/out/m5_model.txt" >&2; exit 1; }

soft_errs() {
  grep -qiE 'error:|unbound variable' "$@"
}

echo "smoke: m5 tests"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m5_test.aura \
  >"$ROOT/out/m5_test.txt" 2>"$ROOT/out/m5_test.err"
T="$ROOT/out/m5_test.txt"
grep -E '^TESTS ' "$T" || true
if ! grep -q '^PAD_M5_TEST_OK$' "$T" || grep -q 'WANT=' "$T" \
   || soft_errs "$T" "$ROOT/out/m5_test.err"; then
  grep -E 'WANT=|FAIL' "$T" >&2 || true
  cat "$ROOT/out/m5_test.err" >&2 || true
  echo "smoke_m5: PAD_M5_TEST_FAIL" >&2
  exit 1
fi
checks=$(sed -n 's/^TESTS checks=\([0-9]*\) fail=0$/\1/p' "$T")
if [[ -z "$checks" || "$checks" -lt 50 ]]; then
  echo "smoke_m5: too few checks (${checks:-none})" >&2
  exit 1
fi
for want in \
  'T HL_COLOR=PKKKKKK.PSSS.SP.CCCC...PS.S.NPP.PQQQQQQQQQQ.TTTTTP.PMMMMMMMMMMMMMMP OK' \
  'T DEF_HELLO=9 OK' \
  'T REF_HELLO_N=3 OK' \
  'T GOTO_OK=ok OK' \
  'T NOSYM=no-symbol OK' \
  'T NODEF=no-def OK' \
  'T Q_REBIND=yes OK' \
  'T USED_DEFLOOKUP=yes OK' \
  'T GAPS_NONE=yes OK' \
  'T JUMP_HOOK=yes OK' \
  'T DEFLOOKUP_HELLO=1 OK'; do
  grep -qF -- "$want" "$T" || { echo "smoke_m5: test missing: $want" >&2; exit 1; }
done
echo "smoke_m5: PAD_M5_TEST_OK checks=$checks"

echo "smoke: m5 HL + jump + query/mutate"
bash "$ROOT/scripts/run_soft.sh" /workspace/aura-pad/soft/pad/m5_smoke.aura \
  >"$ROOT/out/m5_smoke.txt" 2>"$ROOT/out/m5_smoke.err"
cat "$ROOT/out/m5_smoke.txt"
if [[ -s "$ROOT/out/m5_smoke.err" ]]; then
  cat "$ROOT/out/m5_smoke.err" >&2
fi
S="$ROOT/out/m5_smoke.txt"
fail=0
for want in \
  'HL n=67 toks=20 K=1 Q=1 M=1 C=1 T=1 color=PKKKKKK.PSSS.SP.CCCC...PS.S.NPP.PQQQQQQQQQQ.TTTTTP.PMMMMMMMMMMMMMMP' \
  'JUMP cmd=goto-def point=9 refs=1' \
  'JUMP cmd=jump-back point=44 refs=0' \
  'JUMP cmd=find-refs point=44 refs=3' \
  'EXPECT REFS_STR=9.44.55 OK' \
  'REJECT mid=5 reason=no-symbol cmd=goto-def say="put the cursor on a name first"' \
  'REJECT mid=5 reason=no-def cmd=goto-def say="could not find where that name is born"' \
  'REJECT mid=5 reason=nothing-to-back cmd=jump-back say="nowhere to jump back to"' \
  'QUERY load=ok cats=core.stable.def-use.pattern.filter.marker.schema.module.stats.observability' \
  'QUERY find=hello nodes=1 defuse_len=2' \
  'MUTATE total=2 committed=2 rolled=0 safe=yes' \
  'USED define-lookup.query:code.query:ref-counts.query:node-types' \
  'GAPS none' \
  'PAD_M5_OK'; do
  grep -qF -- "$want" "$S" || { echo "smoke_m5: missing: $want" >&2; fail=1; }
done
if grep -q '_FAIL\|WANT=' "$S"; then fail=1; fi
if soft_errs "$S" "$ROOT/out/m5_smoke.err"; then fail=1; fi
if [[ "$fail" -ne 0 ]]; then
  echo "smoke_m5: PAD_M5_OK checks failed" >&2
  exit 1
fi
echo "smoke_m5: PAD_M5_OK"
