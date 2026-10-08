#!/usr/bin/env bash
# Step 35. Who after save and reopen, or an explicit soft-only sentence.
# Includes the undo and reopen markers. The hands-on is sentences.
# Does not call docker. Prints PAD_M20_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/m20"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "smoke_m20: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
doc = (root / "docs/m20.md").read_text(encoding="utf-8")
for need in ("apply keep-hello", "who", "save", "soft-only",
             "GAPS persist-global", "PAD_UNDO_WHO_OK", "PAD_REOPEN_OK"):
    if need not in doc:
        sys.exit("smoke_m20: doc missing " + need)
PY

run_marker() {
  local script="$1" marker="$2" dest="$3"
  bash "$ROOT/scripts/$script" >"$dest" 2>"$dest.err" || {
    cat "$dest" "$dest.err" >&2
    fail "$script failed"
  }
  grep -qx "$marker" "$dest" || fail "missing $marker"
}

run_marker smoke_undo.sh PAD_UNDO_WHO_OK "$OUT/undo.txt"
run_marker smoke_reopen.sh PAD_REOPEN_OK "$OUT/reopen.txt"
echo PAD_M20_OK
