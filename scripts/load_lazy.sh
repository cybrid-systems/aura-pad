#!/usr/bin/env bash
# Step 6. The read stack loads on the first KEY check, not on an arrow.
# Prints PAD_LOAD_LAZY_OK.
# The canary string-join line is not a stand-in for either boolean.
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
  echo "load_lazy: no aura binary" >&2
  exit 1
fi
lib="$(cd "$(dirname "$AURA")/.." && pwd)/lib"
if [[ ! -d "$lib/std" && -d /workspace/aura-grok/lib/std ]]; then
  lib=/workspace/aura-grok/lib
fi
OUT="$ROOT/out/load-lazy"
rm -rf "$OUT"
mkdir -p "$OUT"
printf '(define (hello x) (+ x 1))\n' >"$OUT/hello.aura"

python3 "$ROOT/scripts/paren_check.py" \
  "$ROOT/soft/pad/read.aura" "$ROOT/soft/pad/play.aura"

python3 - "$ROOT" <<'PY'
import sys
root = sys.argv[1]
play = open(root + "/soft/pad/play.aura", encoding="utf-8").read()
read = open(root + "/soft/pad/read.aura", encoding="utf-8").read()
lines = play.splitlines()
top = "\n".join(lines[:41])
bad = []
if "ws.aura" in play or "query.aura" in play:
    bad.append("play.aura names ws.aura or query.aura")
if "read.aura" in top or "ws.aura" in top or "query.aura" in top:
    bad.append("top load list is not editor-only")
if 'KEY check' not in play or "read.aura" not in play:
    bad.append("play.aura does not lazy-load read.aura on KEY check")
if "does not fix aura#4351" not in read:
    bad.append("read.aura does not say this order leaves aura#4351 open")

def strip_comments(src):
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == ";":
            while i < n and src[i] != "\n":
                i += 1
        elif c == '"':
            out.append(c)
            i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\":
                    out.append(src[i])
                    i += 1
                    if i < n:
                        out.append(src[i])
                        i += 1
                else:
                    out.append(src[i])
                    i += 1
            if i < n:
                out.append(src[i])
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)

def body(code, name):
    key = "(define (" + name
    i = code.find(key)
    if i < 0:
        bad.append("missing " + name)
        return ""
    j = code.find("\n(define ", i + 1)
    if j < 0:
        j = len(code)
    return code[i:j]

code = strip_comments(read)
sane = body(code, "pad:read-sane?")
stack = body(code, "pad:read-stack!")
loader = body(code, "pad:read-load!")
canary = body(code, "pad:read-canary!")
for form in ("(null? (list))", "(pair? (null? (list 1)))", "(null? (list 1))"):
    if form not in sane:
        bad.append("pad:read-sane? missing " + form)
if "pad:q-sane?" in sane or "load" in sane or ".aura" in sane:
    bad.append("pad:read-sane? loads or calls pad:q-sane?")
if "pad:read-sane?" not in loader or "pad:read-stack!" not in loader:
    bad.append("pad:read-load! does not record then load")
elif loader.index("pad:read-sane?") > loader.index("pad:read-stack!"):
    bad.append("pad:read-load! loads before the baseline")
order = ("std.aura", "query.aura", "ws.aura", "pad:q-sane?")
pos = -1
for name in order:
    i = stack.find(name)
    if i < 0 or i <= pos:
        bad.append("load order is not std, query, ws, then pad:q-sane?")
        break
    pos = i
if '(string-join (list "a" "b") ",")' not in canary:
    bad.append("canary does not call string-join")
if '(string-join (list "a" "b") ",")' in sane:
    bad.append("baseline uses the canary")
load_path = sane + stack + loader + canary
for banned in ("(set-code", "pad:ws-set-code!", "pad:ws-load!"):
    if banned in load_path:
        bad.append("load path contains " + banned)
for banned in ("string-split", "string-trim", "string-replace"):
    if banned in code:
        bad.append("read.aura contains " + banned)
if bad:
    print("load_lazy source:", "; ".join(bad), file=sys.stderr)
    sys.exit(1)
PY

run_play() {
  AURA_PATH="$lib" AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
    AURA_PAD_HOME="$ROOT" PAD_POLL=0 PAD_DEFER=0 \
    "$AURA" "$ROOT/soft/pad/play.aura"
}

fail() { echo "load_lazy: $*" >&2; exit 1; }

quiet() { # $1 label $2 file
  if grep -qiE 'error:|unbound variable' "$2" "$2.err" 2>/dev/null; then
    fail "$1 Soft error"
  fi
  if grep -q 'READ loaded' "$2"; then
    fail "$1 loaded read.aura"
  fi
  if grep -q 'set_code=' "$2"; then
    fail "$1 printed set_code (ws loaded)"
  fi
  if grep -q 'GAPS read-leak' "$2"; then
    fail "$1 read-leak"
  fi
  grep -q 'SNAP v' "$2" || fail "$1 wrote no frame"
}

ARROWS=$'IN 27 91 65\nIN 27 91 66\nIN 27 91 67\nIN 27 91 68\nIN 27 79 66\nKEY prev-line\nKEY next-line\nKEY left\nKEY right\n'

printf '%sQUIT\n' "$ARROWS" | run_play >"$OUT/arrows.txt" 2>"$OUT/arrows.txt.err" \
  || { cat "$OUT/arrows.txt.err" >&2; exit 1; }
quiet arrows "$OUT/arrows.txt"

printf '%sQUIT\n' "$ARROWS" | PAD_VI=1 run_play >"$OUT/vi-arrows.txt" 2>"$OUT/vi-arrows.txt.err" \
  || { cat "$OUT/vi-arrows.txt.err" >&2; exit 1; }
quiet vi-arrows "$OUT/vi-arrows.txt"

printf '%sQUIT\n' "$ARROWS" | PAD_SENTENCE=1 PAD_VI=1 PAD_FILE="$OUT/hello.aura" \
  run_play >"$OUT/ux-arrows.txt" 2>"$OUT/ux-arrows.txt.err" \
  || { cat "$OUT/ux-arrows.txt.err" >&2; exit 1; }
quiet ux-arrows "$OUT/ux-arrows.txt"
grep -q '^SAY not checked yet$' "$OUT/ux-arrows.txt" || fail "arrow changed the sentence status"
grep -q '^LEGEND > $' "$OUT/ux-arrows.txt" || fail "arrow changed the sentence line"

printf 'KEY check\nQUIT\n' | run_play >"$OUT/check.txt" 2>"$OUT/check.txt.err" \
  || { cat "$OUT/check.txt.err" >&2; exit 1; }
if grep -qiE 'error:|unbound variable' "$OUT/check.txt" "$OUT/check.txt.err"; then
  fail "check Soft error"
fi

python3 - "$OUT/check.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
need = [
    "READ loaded",
    "READ baseline=true",
    "READ loads=std",
    "READ loads=query",
    "READ loads=ws",
    "READ q-sane=true",
    "READ canary=a,b",
    "READ set_code=0",
    "READ state=sane",
]
pos = -1
for line in need:
    i = text.find(line, pos + 1)
    if i < 0:
        # Each probe is its own line. The canary does not imply them.
        print("load_lazy check missing " + line, file=sys.stderr)
        sys.exit(1)
    pos = i
if "GAPS read-leak" in text or "4351" in text or "READ state=insane" in text:
    print("load_lazy check leaked or claimed a fix", file=sys.stderr)
    sys.exit(1)
if text.count("READ loaded") != 1:
    print("load_lazy check loaded read.aura more than once", file=sys.stderr)
    sys.exit(1)
if text.count("READ set_code=0") != 1:
    print("load_lazy check set_code count", file=sys.stderr)
    sys.exit(1)
if "\nSAY sane\n" not in text and not text.endswith("SAY sane\n"):
    # The status word is also the frame SAY after the check.
    if "SAY sane" not in text:
        print("load_lazy check status is not sane", file=sys.stderr)
        sys.exit(1)
PY

# Same session: arrows first, then the one check. The marker is once,
# and it starts after the arrow frames.
printf '%sKEY check\nQUIT\n' "$ARROWS" | run_play >"$OUT/both.txt" 2>"$OUT/both.txt.err" \
  || { cat "$OUT/both.txt.err" >&2; exit 1; }
python3 - "$OUT/both.txt" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
if text.count("READ loaded") != 1:
    print("load_lazy both: read.aura load count", file=sys.stderr)
    sys.exit(1)
head, tail = text.split("READ loaded", 1)
if "SNAP v" not in head or "set_code=" in head or "READ " in head:
    print("load_lazy both: arrows touched the read stack", file=sys.stderr)
    sys.exit(1)
for line in ("READ baseline=true", "READ q-sane=true", "READ canary=a,b",
             "READ set_code=0", "READ state=sane"):
    if line not in tail:
        print("load_lazy both missing " + line, file=sys.stderr)
        sys.exit(1)
if "GAPS read-leak" in text:
    print("load_lazy both: read-leak", file=sys.stderr)
    sys.exit(1)
PY

echo PAD_LOAD_LAZY_OK
