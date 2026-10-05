#!/usr/bin/env python3
"""Host-side MiniMax proposer for aura-pad (keymap param pack).

HTTP stays here. Soft only reads the lambda file this script writes and
gates it (set!/display/eval/load/shell/http bans are Soft's job; this
script pre-filters the same words so a bad reply costs one retry, not a
Soft run).

Pack shape: (lambda () (list step room strict))
  step 1..8 cursor jump, room 1..32 max length, strict 0|1 gentle rules.

Config: $MINIMAX_ENV_FILE or ~/.config/aura-build/minimax.env
  MINIMAX_API_KEY_FILE, MINIMAX_BASE_URL, MINIMAX_MODEL

Default base is https://api.minimax.cn/v1. A configured api.minimaxi.com
host is rewritten to api.minimax.cn. This script never calls api.minimaxi.com.

M3 helper shape (--helper): (lambda () (list TOKEN ...))
  TOKEN is a command word ("left" "right" "home" "end" "back" "open-line"
  "kill-line" "next-line" "prev-line"), "type:<a-z and space>", or a char
  code. Soft plays it on the multi-line buffer toward "hi" / "aura".

Usage: propose_minimax.py OUT_PATH [ROUND [NOTE [PREV_PATH]]]
       propose_minimax.py --helper OUT_PATH [ROUND [NOTE [PREV_PATH]]]
       propose_minimax.py --check   (exit 0 if a key is configured, 3 if not)
Stdout stays empty. Stderr is PROPOSE_WROTE or PROPOSE_FAIL <reason>.
The API key is never printed.
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

CN_BASE = "https://api.minimax.cn/v1"


def _env_file() -> Path | None:
    raw = os.environ.get("MINIMAX_ENV_FILE", "").strip()
    candidates = []
    if raw:
        candidates.append(Path(raw))
    candidates.append(Path.home() / ".config" / "aura-build" / "minimax.env")
    candidates.append(Path("/home/box/.config/aura-build/minimax.env"))
    for p in candidates:
        if p.is_file():
            return p
    return None


def _parse_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def _read_key(env: dict[str, str], env_path: Path) -> str:
    key = os.environ.get("MINIMAX_API_KEY", "").strip()
    if key:
        return key
    file_raw = env.get("MINIMAX_API_KEY_FILE", "").strip()
    candidates = []
    if file_raw:
        candidates.append(Path(file_raw))
        candidates.append(env_path.parent / Path(file_raw).name)
    candidates.append(env_path.parent / "minimax_api_key")
    for p in candidates:
        if p.is_file():
            return p.read_text(encoding="utf-8").strip()
    return ""


def _redact(text: str, key: str) -> str:
    if key and key in text:
        text = text.replace(key, "[redacted]")
    return text


def _base_url(env: dict[str, str]) -> str:
    base = (
        os.environ.get("MINIMAX_BASE_URL", "").strip()
        or env.get("MINIMAX_BASE_URL", "").strip()
        or CN_BASE
    ).rstrip("/")
    # Never call api.minimaxi.com. The product host is api.minimax.cn.
    if "minimaxi.com" in base:
        print("PROPOSE_BASE " + CN_BASE, file=sys.stderr)
        return CN_BASE
    return base


def _balanced(s: str) -> bool:
    n = 0
    for ch in s:
        if ch == "(":
            n += 1
        elif ch == ")":
            n -= 1
            if n < 0:
                return False
    return n == 0


def _extract_lambda(text: str) -> str:
    if not text:
        return ""
    fence = re.search(r"```(?:aura|scheme|lisp)?\s*([\s\S]*?)```", text, re.I)
    body = fence.group(1) if fence else text
    start = body.find("(lambda")
    if start < 0:
        return ""
    n = 0
    end = -1
    for i, ch in enumerate(body[start:], start):
        if ch == "(":
            n += 1
        elif ch == ")":
            n -= 1
            if n == 0:
                end = i + 1
                break
    if end < 0:
        return ""
    line = " ".join(body[start:end].split())
    if not line.startswith("(lambda"):
        return ""
    if "list" not in line:
        return ""
    if not _balanced(line):
        return ""
    return line


def _prompt(rnd: int, note: str, prev: str) -> str:
    prev_s = prev.strip() if prev else "none"
    # Round-stamped integers so the model cannot copy the previous body.
    step = 1 + (rnd % 3)
    room = 10 + (rnd % 7)
    strict = rnd % 2
    example = f"(lambda () (list {step} {room} {strict}))"
    return (
        "Return ONLY one Aura line of the form (lambda () (list step room strict)). "
        f"You are proposing a keymap param pack for a kid-friendly text editor, round {rnd}. "
        "A seeded sequence of 24 keys is replayed: left, right, insert-letter, "
        "delete-back, insert-space, home/end. The goal text is \"hi aura\". "
        "Score = accepted_edits - 2*rejected_keys - distance_from_goal. "
        "step is the cursor jump for left/right (1..8, clamped at edges). "
        "room is the max buffer length before inserts are refused (1..32). "
        "strict is 0 or 1: 1 refuses moving past the edges and odd letters "
        "and makes key 5 jump to end; 0 clamps moves, accepts any letter, key 5 jumps home. "
        "The current main pack is (list 3 20 0). "
        "All three must be integers. "
        "ONLY use: lambda, list, and non-negative integers in parentheses. "
        "Do NOT use set!, begin, display, write, mutate, eval, load, shell, http, "
        "modulo, quotient, or division. No markdown. "
        "Change at least one field from the previous lambda. "
        f"Previous lambda (do not repeat it verbatim): {prev_s}. "
        f"Last note: {note}. "
        f"Shape example, change it: {example}"
    )


HELPER_CMDS = (
    "left", "right", "home", "end", "back",
    "open-line", "kill-line", "next-line", "prev-line",
)
HELPER_MAIN = (
    '(lambda () (list "kill-line" "type:hi" "open-line" "next-line" "type:au"))'
)


def _prompt_helper(rnd: int, note: str, prev: str) -> str:
    prev_s = prev.strip() if prev else "none"
    return (
        "Return ONLY one Aura line of the form (lambda () (list TOKEN ...)). "
        f"You are proposing a command helper for a kid-friendly multi-line text editor, round {rnd}. "
        "The buffer starts as ONE line with the text \"nwn\" and the cursor at line 0, column 0. "
        "The goal is TWO lines: line 0 is \"hi\" and line 1 is \"aura\". "
        "Each TOKEN is a double-quoted string: one of \"left\" \"right\" \"home\" \"end\" \"back\" "
        "\"open-line\" \"kill-line\" \"next-line\" \"prev-line\", or \"type:TEXT\" where TEXT is "
        "lowercase a-z or spaces (one key per letter). "
        "open-line splits the line at the cursor and the cursor STAYS on the current line (like Emacs C-o). "
        "kill-line deletes from the cursor to the end of the line; at the end of a line it joins the next line. "
        "next-line / prev-line move one line keeping the column (clamped). "
        "Refused keys: left at the very start (too-far), next-line on the last line (no-line), "
        "prev-line on line 0 (no-line), kill-line on an empty buffer (empty-buf). "
        "Score = 40 - accepted_keys - 2*refused_keys - 3*distance_from_goal. Higher is better. "
        f"The current main helper is {HELPER_MAIN} scoring 27 (it ends with \"hi\" / \"au\"). "
        "Beat it strictly. At most 32 tokens. "
        "Do NOT use set!, begin, display, write, eval, load, shell, http, define, or any other function. "
        "No markdown. "
        f"Previous lambda (do not repeat it verbatim): {prev_s}. "
        f"Last note: {note}."
    )


def _looks_like_helper(lam: str) -> bool:
    m = re.match(r"^\(lambda\s*\(\s*\)\s*\(list\s+(.*)\)\s*\)$", lam)
    if not m:
        return False
    toks = re.findall(r'"[^"]*"|\d+|\S+', m.group(1))
    if not toks or len(toks) > 32:
        return False
    for t in toks:
        if t.isdigit():
            continue
        if not (t.startswith('"') and t.endswith('"')):
            return False
        word = t[1:-1]
        if word in HELPER_CMDS:
            continue
        if word.startswith("type:") and re.fullmatch(r"[a-z ]*", word[5:]):
            continue
        return False
    return True


def _banned(lam: str) -> str:
    banned = (
        "set!",
        "vector-set!",
        "begin",
        "display",
        "write",
        "mutate",
        "eval",
        "load",
        "shell",
        "http",
        "mod",
        "modulo",
        "floor",
        "quotient",
    )
    low = lam.lower()
    for b in banned:
        if b.lower() in low:
            return b
    if " / " in lam or "(/" in lam:
        return "/"
    return ""


def _looks_like_pack(lam: str) -> bool:
    # (lambda () (list N N N)) with optional whitespace already collapsed.
    m = re.match(
        r"^\(lambda\s*\(\s*\)\s*\(list\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)\s*\)\s*\)$",
        lam,
    )
    if not m:
        return False
    step, room, strict = (int(m.group(i)) for i in range(1, 4))
    if step < 1 or step > 8:
        return False
    if room < 1 or room > 32:
        return False
    if strict not in (0, 1):
        return False
    return True


def _call(base: str, key: str, model: str, prompt: str, temperature: float) -> str:
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You output a single Aura lambda and nothing else."},
            {"role": "user", "content": prompt},
        ],
        "temperature": temperature,
        "max_tokens": 256,
        "thinking": {"type": "disabled"},
    }
    req = urllib.request.Request(
        f"{base}/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    return str(payload["choices"][0]["message"]["content"] or "")


def _check() -> int:
    env_path = _env_file()
    if env_path is None:
        print("PROPOSE_KEY none", file=sys.stderr)
        return 3
    if not _read_key(_parse_env(env_path), env_path):
        print("PROPOSE_KEY none", file=sys.stderr)
        return 3
    print("PROPOSE_KEY present", file=sys.stderr)
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--check":
        return _check()
    helper = False
    if len(sys.argv) >= 2 and sys.argv[1] == "--helper":
        helper = True
        del sys.argv[1]
    if len(sys.argv) < 2 or len(sys.argv) > 5:
        print("PROPOSE_FAIL usage", file=sys.stderr)
        return 2
    out = Path(sys.argv[1])
    rnd = 1
    note = "none"
    prev = ""
    if len(sys.argv) >= 3:
        try:
            rnd = int(sys.argv[2])
        except ValueError:
            rnd = 1
    if len(sys.argv) >= 4:
        note = sys.argv[3].replace("\n", " ")[:180]
    if len(sys.argv) >= 5 and sys.argv[4]:
        pp = Path(sys.argv[4])
        if pp.is_file():
            prev = " ".join(pp.read_text(encoding="utf-8").split())
    env_path = _env_file()
    if env_path is None:
        print("PROPOSE_FAIL no_env", file=sys.stderr)
        return 1
    env = _parse_env(env_path)
    key = _read_key(env, env_path)
    if not key:
        print("PROPOSE_FAIL no_key", file=sys.stderr)
        return 1
    base = _base_url(env)
    model = (
        os.environ.get("MINIMAX_MODEL", "").strip()
        or env.get("MINIMAX_MODEL", "").strip()
        or "MiniMax-M3"
    )
    prompt = _prompt_helper(rnd, note, prev) if helper else _prompt(rnd, note, prev)
    shape_ok = _looks_like_helper if helper else _looks_like_pack
    lam = ""
    last_fail = "no_lambda"
    for _attempt, temp in ((1, 0.4), (2, 0.8)):
        try:
            content = _call(base, key, model, prompt, temp)
        except urllib.error.HTTPError as exc:
            err = exc.read().decode("utf-8", errors="replace")[:300]
            print("PROPOSE_FAIL http_" + str(exc.code) + " " + _redact(err, key), file=sys.stderr)
            return 1
        except Exception as exc:  # noqa: BLE001
            print("PROPOSE_FAIL " + _redact(type(exc).__name__, key), file=sys.stderr)
            return 1
        cand = _extract_lambda(content)
        if not cand.startswith("(lambda"):
            last_fail = "no_lambda"
            continue
        bad = _banned(cand)
        if bad:
            last_fail = "banned_" + bad.replace("!", "").strip()
            continue
        if not shape_ok(cand):
            last_fail = "shape"
            continue
        if prev and cand == prev:
            last_fail = "repeat"
            prompt = prompt + " The previous attempt repeated the prior lambda. Change a number."
            continue
        lam = cand
        break
    if not lam:
        print("PROPOSE_FAIL " + last_fail, file=sys.stderr)
        return 1
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(lam + "\n", encoding="utf-8")
    print("PROPOSE_WROTE", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
