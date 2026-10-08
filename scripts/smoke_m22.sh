#!/usr/bin/env bash
# Step 48. Two proposals, the higher score marked.
# Moving onto the lower score and confirming leaves the page.
# Does not call docker. Does not call intend. Prints PAD_M22_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/m22"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "smoke_m22: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
doc = (root / "docs/m22.md").read_text(encoding="utf-8")
for need in ("PAD_M22_OK", "does not call docker", "does not call `intend`",
             "propose_two.txt", "> a   b", "that one is not better",
             "byte 9", "byte 13", "neither is better", "touches hello",
             "TX_DISAGREE", "WORLD line=fiber_live",
             "WORLD line=host-sequential", "PAD_TX_WORSE_OK",
             "propose_tie.txt", ";; keep this"):
    if need not in doc:
        sys.exit("smoke_m22: doc missing " + need)
for rel in ("soft/pad/worse_tx_test.aura", "soft/pad/tie_tx_test.aura",
            "soft/pad/world_tx_test.aura", "soft/pad/blast_tx_test.aura"):
    src = (root / rel).read_text(encoding="utf-8")
    if "(intend" in src or "intend-history" in src:
        sys.exit("smoke_m22: hands-on calls intend " + rel)
PY

run_marker() {
  local script="$1" marker="$2" dest="$3"
  bash "$ROOT/scripts/$script" >"$dest" 2>"$dest.err" || {
    cat "$dest" "$dest.err" >&2
    fail "$script failed"
  }
  grep -qx "$marker" "$dest" || fail "missing $marker"
}

run_marker smoke_tx_two.sh PAD_TX_TWO_OK "$OUT/two.txt"
run_marker smoke_tx_world.sh PAD_TX_WORLD_OK "$OUT/world.txt"
run_marker smoke_tx_blast.sh PAD_TX_BLAST_OK "$OUT/blast.txt"
run_marker smoke_tx_tie.sh PAD_TX_TIE_OK "$OUT/tie.txt"
run_marker smoke_tx_worse.sh PAD_TX_WORSE_OK "$OUT/worse.txt"
echo PAD_M22_OK
