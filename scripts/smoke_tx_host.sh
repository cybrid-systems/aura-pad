#!/usr/bin/env bash
# Step 36. The host proposer prints a fixture when PAD_LIVE=0.
# It does not read the network and it does not print a key.
# Does not call docker. Prints PAD_TX_HOST_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/tx-host"
rm -rf "$OUT"
mkdir -p "$OUT"
PY="$ROOT/scripts/propose_tx.py"

fail() { echo "smoke_tx_host: $*" >&2; exit 1; }

python3 - "$PY" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
if "deepseek-flash" not in src:
    sys.exit("smoke_tx_host: default model is not deepseek-flash")
if "minimax" not in src:
    sys.exit("smoke_tx_host: minimax adapter is missing")
if "urlopen" in src or "http-post" in src or "socket" in src:
    sys.exit("smoke_tx_host: offline proposer posts")
PY

run_off() {
  local dest="$1"
  shift
  env "$@" python3 "$PY" >"$dest" 2>"$dest.err" || fail "fixture run failed"
}

run_off "$OUT/ok.txt" PAD_LIVE=0
run_off "$OUT/unset.txt" PAD_LIVE=
cmp -s "$OUT/ok.txt" "$ROOT/soft/pad/fixtures/propose_ok.txt" || fail "ok fixture drifted"
cmp -s "$OUT/unset.txt" "$ROOT/soft/pad/fixtures/propose_ok.txt" || fail "unset live drifted"

env PAD_LIVE=0 python3 "$PY" propose_bad_type.txt >"$OUT/bad.txt" 2>"$OUT/bad.err" \
  || fail "bad fixture failed"
cmp -s "$OUT/bad.txt" "$ROOT/soft/pad/fixtures/propose_bad_type.txt" || fail "bad fixture drifted"

python3 - "$OUT/ok.txt" "$OUT/bad.txt" <<'PY'
import pathlib, sys
for path in sys.argv[1:]:
    lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
    ops = [ln for ln in lines if "=(lambda " in ln]
    checks = [ln for ln in lines if ln.startswith("check ")]
    if not ops or not checks:
        sys.exit("smoke_tx_host: missing op or check in " + path)
PY

sentinel="SENTINEL_KEY_do_not_leak_tx"
home="$OUT/home"
mkdir -p "$home/code/keys"
printf '%s\n' "$sentinel" >"$home/code/keys/deepseek"
env HOME="$home" DEEPSEEK_API_KEY="$sentinel" PAD_LIVE=0 \
  python3 "$PY" >"$OUT/keyed.txt" 2>"$OUT/keyed.err" || fail "keyed offline failed"
if grep -q "$sentinel" "$OUT/keyed.txt" "$OUT/keyed.err"; then
  fail "key reached offline output"
fi
cmp -s "$OUT/keyed.txt" "$ROOT/soft/pad/fixtures/propose_ok.txt" || fail "key changed the fixture"

env HOME="$home" DEEPSEEK_API_KEY="$sentinel" PAD_LIVE=1 \
  python3 "$PY" >"$OUT/live.txt" 2>"$OUT/live.err" && fail "live should not post"
if grep -q "$sentinel" "$OUT/live.txt" "$OUT/live.err"; then
  fail "key reached live output"
fi
grep -q "model=deepseek-flash" "$OUT/live.err" || fail "live model was not deepseek-flash"
if [[ -s "$OUT/live.txt" ]]; then
  fail "live wrote a proposal without posting"
fi

env PAD_LIVE=0 python3 "$PY" ../propose_ok.txt >"$OUT/escape.txt" 2>"$OUT/escape.err" \
  && fail "path escape was accepted"
if [[ -s "$OUT/escape.txt" ]]; then
  fail "path escape wrote stdout"
fi

python3 - "$PY" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("propose_tx", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
if mod.DEFAULT_MODEL != "deepseek-flash":
    sys.exit("smoke_tx_host: DEFAULT_MODEL")
if "minimax" not in mod.ADAPTERS:
    sys.exit("smoke_tx_host: ADAPTERS")
if mod.model_name("") != "deepseek-flash":
    sys.exit("smoke_tx_host: default adapter model")
if mod.model_name("minimax") == "deepseek-flash":
    sys.exit("smoke_tx_host: minimax is the default model")
PY

echo PAD_TX_HOST_OK
