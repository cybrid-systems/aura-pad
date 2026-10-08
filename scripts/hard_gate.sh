#!/usr/bin/env bash
# Step 10. Both launch paths pass AURA_MUTATE_TYPE_GATE.
# Unset or empty becomes hard. An external value is kept.
# PAD_VI still comes from vi_flag(), whose default is "1".
# A gate that is not hard makes the probe print GAPS type-gate.
# Prints PAD_HARD_GATE_OK. Does not call docker.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA="${AURA_BIN:-}"
if [[ -z "$AURA" || ! -x "$AURA" ]]; then
  for c in /workspace/aura-grok/build/aura \
           "$HOME/code/grok-dev/aura-grok/build/aura" \
           /home/dev/code/grok-dev/aura-grok/build/aura; do
    if [[ -x "$c" ]]; then AURA="$c"; break; fi
  done
fi
if [[ -z "${AURA:-}" || ! -x "$AURA" ]]; then
  echo "hard_gate: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
if ! command -v cc >/dev/null 2>&1; then
  echo "hard_gate: no host cc" >&2
  exit 1
fi
OUT="$ROOT/out/hard-gate"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/type_gate.aura" \
  "$ROOT/soft/pad/type_gate_test.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
text = (root / "c/aura_pad.c").read_text(encoding="utf-8")
play = (root / "soft/pad/play.aura").read_text(encoding="utf-8")
probe = (root / "soft/pad/type_gate.aura").read_text(encoding="utf-8")

def body(src, sig):
    i = src.find(sig)
    if i < 0:
        sys.exit("hard_gate: missing " + sig)
    j = src.find("\nstatic ", i + len(sig))
    if j < 0:
        j = len(src)
    return src[i:j]

vi = body(text, "static const char *vi_flag")
tg = body(text, "static const char *type_gate")
ch = body(text, "static void child_env")
ba = body(text, "static int build_argv")
if 'return "1";' not in vi:
    sys.exit("hard_gate: vi_flag default is not 1")
if "AURA_MUTATE_TYPE_GATE" in vi or "PAD_SENTENCE" in vi:
    sys.exit("hard_gate: vi_flag changed")
if "PAD_SENTENCE" in text:
    sys.exit("hard_gate: aura_pad.c sets PAD_SENTENCE")
if 'getenv("AURA_MUTATE_TYPE_GATE")' not in tg or 'return "hard";' not in tg:
    sys.exit("hard_gate: type_gate does not default to hard")
if "strcmp" in tg or "strncmp" in tg:
    sys.exit("hard_gate: type_gate compares the value")
if 'setenv("AURA_MUTATE_TYPE_GATE"' not in ch or "type_gate()" not in ch:
    sys.exit("hard_gate: child_env does not assign the gate")
if "AURA_MUTATE_TYPE_GATE=%s" not in ba or "type_gate()" not in ba:
    sys.exit("hard_gate: build_argv does not assign the gate")
if ba.find("!L->docker_mode") < 0 or ba.find("!L->docker_mode") > ba.find("AURA_MUTATE_TYPE_GATE"):
    sys.exit("hard_gate: docker -e is not on the docker path")
if text.count("type_gate()") != 2:
    sys.exit("hard_gate: type_gate() is used outside the two launch sites")
for line in text.splitlines():
    if "strcmp" in line and ("TYPE_GATE" in line or '"hard"' in line or '"soft"' in line):
        sys.exit("hard_gate: C branches on the gate value")
for path in (root / "c").glob("*.c"):
    if path.name == "aura_pad.c":
        continue
    if "AURA_MUTATE_TYPE_GATE" in path.read_text(encoding="utf-8"):
        sys.exit("hard_gate: " + path.name + " reads the gate")
if "type_gate" in play:
    sys.exit("hard_gate: play.aura loads the probe")
if '(display "GAPS type-gate")' not in probe:
    sys.exit("hard_gate: probe does not print GAPS type-gate")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in probe:
        sys.exit("hard_gate: probe uses " + banned)
PY

# Host cc. build_c.sh uses docker only when PAD_C_DOCKER=1 or cc is missing.
PAD_C_DOCKER=0 bash "$ROOT/scripts/build_c.sh" >/dev/null
PAD="$ROOT/out/c/aura-pad"
if [[ ! -x "$PAD" ]]; then
  echo "hard_gate: aura-pad did not build" >&2
  exit 1
fi

cat >"$OUT/aura-wrap" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-e" ]; then
  exit 0
fi
out="${PAD_GATE_OUT:-}"
if [ -n "$out" ]; then
  printf 'GATE=%s\nVI=%s\n' "${AURA_MUTATE_TYPE_GATE-}" "${PAD_VI-}" >"$out"
fi
exit 0
EOF
chmod 755 "$OUT/aura-wrap"

fail() { echo "hard_gate: $*" >&2; exit 1; }

# $1 env file. Remaining args are env assignments for this launch.
# The wrapper is AURA_BIN, so the native child is this script, not Aura.
# It exits before a snapshot. The viewport then reports that and returns.
launch() {
  local dest="$1"
  shift
  env -u AURA_MUTATE_TYPE_GATE -u PAD_VI \
    AURA_PATH="$lib" AURA_PAD_HOME="$ROOT" AURA_BIN="$OUT/aura-wrap" \
    PAD_GATE_OUT="$dest" \
    "$@" \
    "$PAD" </dev/null >"$dest.stdout" 2>"$dest.stderr" || true
  if [[ ! -f "$dest" ]]; then
    cat "$dest.stderr" >&2
    fail "launcher did not start the child ($dest)"
  fi
}

launch "$OUT/unset.env"
grep -qx 'GATE=hard' "$OUT/unset.env" || fail "unset gate was not hard: $(cat "$OUT/unset.env")"
grep -qx 'VI=1' "$OUT/unset.env" || fail "default PAD_VI was not 1: $(cat "$OUT/unset.env")"

launch "$OUT/empty.env" AURA_MUTATE_TYPE_GATE=
grep -qx 'GATE=hard' "$OUT/empty.env" || fail "empty gate was not hard: $(cat "$OUT/empty.env")"

launch "$OUT/soft.env" AURA_MUTATE_TYPE_GATE=soft
grep -qx 'GATE=soft' "$OUT/soft.env" || fail "external soft was overwritten: $(cat "$OUT/soft.env")"
grep -qx 'VI=1' "$OUT/soft.env" || fail "soft launch changed PAD_VI: $(cat "$OUT/soft.env")"

launch "$OUT/hard.env" AURA_MUTATE_TYPE_GATE=hard
grep -qx 'GATE=hard' "$OUT/hard.env" || fail "external hard was overwritten: $(cat "$OUT/hard.env")"

launch "$OUT/vi0.env" PAD_VI=0
grep -qx 'GATE=hard' "$OUT/vi0.env" || fail "PAD_VI=0 launch lost the gate: $(cat "$OUT/vi0.env")"
grep -qx 'VI=0' "$OUT/vi0.env" || fail "PAD_VI=0 was overwritten: $(cat "$OUT/vi0.env")"

# --where prints argv and does not apply child_env. Native argv is the
# aura binary plus play.aura, so the gate is not visible there.
# The docker -e line is checked from source above. This process does not
# run docker.

run_probe() {
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/type_gate_test.aura"
}

AURA_MUTATE_TYPE_GATE=soft run_probe >"$OUT/probe-soft.txt" 2>"$OUT/probe-soft.err" \
  || { cat "$OUT/probe-soft.err" >&2; exit 1; }
grep -qx 'GAPS type-gate' "$OUT/probe-soft.txt" || fail "soft probe did not print GAPS type-gate"
grep -qx 'PROBE other' "$OUT/probe-soft.txt" || fail "soft probe did not finish"

AURA_MUTATE_TYPE_GATE=hard run_probe >"$OUT/probe-hard.txt" 2>"$OUT/probe-hard.err" \
  || { cat "$OUT/probe-hard.err" >&2; exit 1; }
if grep -q 'GAPS type-gate' "$OUT/probe-hard.txt"; then
  fail "hard probe printed GAPS type-gate"
fi
grep -qx 'PROBE hard' "$OUT/probe-hard.txt" || fail "hard probe did not finish"

(
  unset AURA_MUTATE_TYPE_GATE
  run_probe
) >"$OUT/probe-unset.txt" 2>"$OUT/probe-unset.err" \
  || { cat "$OUT/probe-unset.err" >&2; exit 1; }
grep -qx 'GAPS type-gate' "$OUT/probe-unset.txt" || fail "direct aura without the launcher hid a missing gate"
grep -qx 'PROBE other' "$OUT/probe-unset.txt" || fail "unset probe did not finish"

if grep -qiE 'error:|unbound variable' "$OUT"/probe-*.txt "$OUT"/probe-*.err; then
  fail "Soft error"
fi

echo PAD_HARD_GATE_OK
