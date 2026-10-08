#!/usr/bin/env bash
# Step 11. Refuse unsafe top-level forms and unsafe init heads.
# set-code does not run. The lib refusal count is logged, not locked.
# Prints PAD_READ_GUARD_OK. Does not call docker.
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
  echo "read_guard: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/read-guard"
rm -rf "$OUT"
mkdir -p "$OUT"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/read.aura" \
  "$ROOT/soft/pad/read_guard_test.aura" \
  "$ROOT/soft/pad/ux.aura"

python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
src = (root / "soft/pad/read.aura").read_text(encoding="utf-8")
test = (root / "soft/pad/read_guard_test.aura").read_text(encoding="utf-8")
pen = (root / "soft/pad/pen.aura").read_text(encoding="utf-8")

def body(name):
    key = "(define (" + name
    i = src.find(key)
    if i < 0:
        sys.exit("read_guard: missing " + name)
    j = src.find("\n(define ", i + 1)
    if j < 0:
        j = len(src)
    return src[i:j]

check = body("pad:read-check! ")
refuse = body("pad:read-refuse!)")
guard = body("pad:read-guard? ")
gsrc = body("pad:read-guard-src? ")
if "pad:read-guard?" not in check or "pad:read-refuse!" not in check:
    sys.exit("read_guard: check does not scan before set-code")
if check.find("pad:read-guard?") > check.find("workspace :create"):
    sys.exit("read_guard: set-code world is created before the scan")
for banned in ("pad:ws-set-code!", "set-code", "eval-current"):
    if banned in refuse or banned in guard or banned in gsrc:
        sys.exit("read_guard: refuse path calls " + banned)
if "pad:hl-tokens" not in gsrc:
    sys.exit("read_guard: scan does not read pad:hl-tokens")
if '"P"' not in src:
    sys.exit("read_guard: scan does not use paren tokens")
for name in ("require", "load", "display", "write-file", "set-code"):
    if f'(string=? s "{name}")' not in src:
        sys.exit("read_guard: missing call head " + name)
if "*pen-banned*" in src or "pad:pen-" in src:
    sys.exit("read_guard: scan uses the pen word list")
if "string-contains?" in gsrc or "string-contains?" in guard:
    sys.exit("read_guard: scan walks source text")
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in src or banned in test:
        sys.exit("read_guard: banned text " + banned)
if "aura did not check this file: it loads other code" not in src:
    sys.exit("read_guard: SAY sentence missing")
if "33" in test or "35" in test:
    sys.exit("read_guard: lib count is locked")
if "*pen-banned*" in test:
    sys.exit("read_guard: test scans with the pen list")
# The pen list stays the old substring gate. This step does not retarget it.
if "*pen-banned*" not in pen:
    sys.exit("read_guard: pen list disappeared")
PY

python3 - "$lib" "$OUT/paths.aura" <<'PY'
import pathlib, sys
lib = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
files = sorted(p for p in lib.rglob("*.aura") if p.is_file())
if not files:
    sys.exit("read_guard: no lib sources")
lines = ["(define *guard-paths*", "  (list"]
for path in files:
    lines.append('    "' + str(path) + '"')
lines.append("))")
dest.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("read_guard: lib files", len(files))
PY

# Count driver. One file at a time so a scan's garbage can be dropped
# before the next file. It calls pad:read-guard-src?, not the pen list.
cat >"$OUT/slim_guard.aura" <<'EOF'
(define *pad-home*
  (let ((h (getenv "AURA_PAD_HOME")))
    (if (and (string? h) (> (string-length h) 0)) h "/workspace/aura-pad")))
(define *read-ready* #f)
(define *pl-say* "")
(load (string-append *pad-home* "/soft/pad/hl.aura"))
(load (string-append *pad-home* "/soft/pad/read.aura"))
(load (getenv "PAD_GUARD_PATHS"))
(define (rg:one path)
  (let ((raw (read-file path)))
    (if (and (string? raw) (pad:read-guard-src? raw)) 1 0)))
(define (rg:count paths n)
  (if (null? paths)
      n
      (rg:count (cdr paths) (+ n (rg:one (car paths))))))
(display "GUARD lib-refuse=")
(display (number->string (rg:count *guard-paths* 0)))
(newline)
EOF

fail() { echo "read_guard: $*" >&2; exit 1; }

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  "$AURA" "$ROOT/soft/pad/read_guard_test.aura" >"$OUT/unit.txt" 2>"$OUT/unit.err" \
  || { cat "$OUT/unit.err" >&2; exit 1; }

if grep -qiE 'error:|unbound variable' "$OUT/unit.txt" "$OUT/unit.err"; then
  cat "$OUT/unit.txt" "$OUT/unit.err" >&2
  fail "Soft error"
fi
grep -qx 'GUARD_UNIT_OK' "$OUT/unit.txt" || { cat "$OUT/unit.txt" "$OUT/unit.err" >&2; fail "unit did not finish"; }
grep -qx 'GUARD fn-name=ok' "$OUT/unit.txt" || fail "a function named display was a call"
grep -qx 'GUARD bind-name=ok' "$OUT/unit.txt" || fail "a let binding named display was a call"
grep -qx 'GUARD arg-name=ok' "$OUT/unit.txt" || fail "a lambda arg named require was a call"
grep -qx 'GUARD text=ok' "$OUT/unit.txt" || fail "comment or string text was a call head"

say='aura did not check this file: it loads other code'
for label in top-require top-display def-display def-require def-load def-write \
             def-set def-begin def-lambda let-require let-load let-display \
             let-write let-set let-init; do
  grep -qx "BAD ${label} set=0 status=fail say=${say}" "$OUT/unit.txt" \
    || fail "$label was checked or set-code ran"
done

grep -qx 'SAFE set=1' "$OUT/unit.txt" || fail "safe define and export were refused"
grep -qx 'SAFE status=checked' "$OUT/unit.txt" || fail "safe page was not checked"
grep -qx 'SAFE root=same' "$OUT/unit.txt" || fail "safe check changed the root"
grep -qx 'SAFE say=clear' "$OUT/unit.txt" || fail "safe check kept the refusal"

AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  AURA_MUTATE_TYPE_GATE=hard AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
  PAD_GUARD_PATHS="$OUT/paths.aura" \
  "$AURA" "$OUT/slim_guard.aura" >"$OUT/lib.txt" 2>"$OUT/lib.err" \
  || { cat "$OUT/lib.err" >&2; exit 1; }
if grep -qiE 'error:|unbound variable' "$OUT/lib.txt" "$OUT/lib.err"; then
  cat "$OUT/lib.txt" "$OUT/lib.err" >&2
  fail "lib scan failed"
fi
if ! grep -qE '^GUARD lib-refuse=[0-9]+$' "$OUT/lib.txt"; then
  fail "lib refusal count was not printed"
fi
# The number is evidence. 33 and 35 are not gates.
count="$(sed -n 's/^GUARD lib-refuse=//p' "$OUT/lib.txt")"
echo "read_guard: lib refusals ${count}"

echo PAD_READ_GUARD_OK
