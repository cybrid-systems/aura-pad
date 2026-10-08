#!/usr/bin/env bash
# Step 54. A story uses the same card and the same undo.
# Does not call docker. Does not set PAD_CLASSIC. Prints PAD_M23_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/m23"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() { echo "smoke_m23: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
doc = (root / "docs/m23.md").read_text(encoding="utf-8")
for need in ("PAD_M23_OK", "does not call docker", "does not set `PAD_CLASSIC`",
             "three sentences", "make the last line kinder", "KEEP", "undo",
             "story_kinder.txt", "the cat dreamed", "let's use kind words",
             "not aura code", "not a story", "nobody.nobody.nobody",
             "PAD_STORY_KIND_OK"):
    if need not in doc:
        sys.exit("smoke_m23: doc missing " + need)
tut = (root / "docs/tutorial.md").read_text(encoding="utf-8")
if "make the last line kinder" in tut:
    sys.exit("smoke_m23: tutorial.md was extended")
PY

run_marker() {
  local script="$1" marker="$2" dest="$3"
  bash "$ROOT/scripts/$script" >"$dest" 2>"$dest.err" || {
    cat "$dest" "$dest.err" >&2
    fail "$script failed"
  }
  grep -qx "$marker" "$dest" || fail "missing $marker"
}

run_marker smoke_story_open.sh PAD_STORY_OPEN_OK "$OUT/open.txt"
run_marker smoke_story_def.sh PAD_STORY_DEF_OK "$OUT/def.txt"
run_marker smoke_story_why.sh PAD_STORY_WHY_OK "$OUT/why.txt"
run_marker smoke_story_tx.sh PAD_STORY_TX_OK "$OUT/tx.txt"
run_marker smoke_story_kind.sh PAD_STORY_KIND_OK "$OUT/kind.txt"
echo PAD_M23_OK
