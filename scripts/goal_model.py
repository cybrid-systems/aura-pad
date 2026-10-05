#!/usr/bin/env python3
"""Host model of the Soft M8 intent worldline (soft/pad/goal.aura).

Re-computes story scores for the M8 fixtures so smoke can assert
CARD a=.. b=.. KEEP=.. without trusting Soft alone.
Score: base - keys - 2*rejects - 3*dist - 4*unkind  (base=40).
Goal default: "hi" / "aura". Start: one noise line from seed 20261005.
`goal_model.py --check` -> PAD_M8_MODEL_OK.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED = 20261005
BASE = 40
GOAL = ["hi", "aura"]
MEAN = ("stupid", "dumb", "hate", "idiot", "shut up")
MAX_COL = 12
MAX_LINES = 4
LINE_CMDS = {
    "left", "right", "home", "end", "back",
    "open-line", "kill-line", "next-line", "prev-line",
}


def seed_step(r: int) -> int:
    return (r * 1103515245 + 12345) & 0x7FFFFFFF


def start_lines() -> list[list[int]]:
    r = SEED
    acc: list[int] = []
    for _ in range(3):
        r = seed_step(r)
        acc.append(97 + (r % 26))
    return [acc]


def dist_line(a: list[int], b: list[int]) -> int:
    d = 0
    n = max(len(a), len(b))
    for i in range(n):
        if i >= len(a) or i >= len(b) or a[i] != b[i]:
            # Soft pad:dist is positional mismatch + length gap
            pass
    i = 0
    while i < len(a) or i < len(b):
        if i >= len(a):
            return d + (len(b) - i)
        if i >= len(b):
            return d + (len(a) - i)
        if a[i] != b[i]:
            d += 1
        i += 1
    return d


def dist_lines(L: list[list[int]], G: list[list[int]]) -> int:
    d = 0
    i = 0
    while i < len(L) or i < len(G):
        if i >= len(L):
            d += len(G[i]) + 1
            i += 1
            continue
        if i >= len(G):
            d += len(L[i]) + 1
            i += 1
            continue
        d += dist_line(L[i], G[i])
        i += 1
    return d


def codes(s: str) -> list[int]:
    return [ord(c) for c in s]


def expand(plan: list) -> list:
    out = []
    for tok in plan:
        if isinstance(tok, str) and tok.startswith("type:"):
            out.extend(codes(tok[5:]))
        else:
            out.append(tok)
    return out


def mean_word(s: str) -> str:
    for w in MEAN:
        if w in s:
            return w
    return ""


def unkind(plan: list) -> int:
    n = 0
    for tok in plan:
        if isinstance(tok, str) and tok.startswith("type:"):
            if mean_word(tok[5:]):
                n += 1
        elif isinstance(tok, str) and mean_word(tok):
            n += 1
    return n


def gate(c, L, l, col):
    n = len(L)
    ln = L[l]
    length = len(ln)
    empty = n == 1 and length == 0
    if isinstance(c, int):
        if not (c == 32 or 97 <= c <= 122):
            return "not-print"
        if length >= MAX_COL:
            return "need-space"
        return "ok"
    if not isinstance(c, str) or c not in LINE_CMDS:
        return "not-a-key"
    if c == "left" and l == 0 and col == 0:
        return "too-far"
    if c == "right" and l == n - 1 and col >= length:
        return "too-far"
    if c == "next-line" and l >= n - 1:
        return "no-line"
    if c == "prev-line" and l == 0:
        return "no-line"
    if c == "back" and empty:
        return "empty-buf"
    if c == "back" and l == 0 and col == 0:
        return "too-far"
    if c == "kill-line" and empty:
        return "empty-buf"
    if c == "kill-line" and col >= length and l >= n - 1:
        return "no-line"
    if c == "open-line" and n >= MAX_LINES:
        return "need-space"
    return "ok"


def apply_cmd(c, L, l, col):
    L = [row[:] for row in L]
    ln = L[l]
    length = len(ln)
    if isinstance(c, int):
        L[l] = ln[:col] + [c] + ln[col:]
        return L, l, col + 1
    if c == "left":
        if col > 0:
            return L, l, col - 1
        return L, l - 1, len(L[l - 1])
    if c == "right":
        if col < length:
            return L, l, col + 1
        return L, l + 1, 0
    if c == "home":
        return L, l, 0
    if c == "end":
        return L, l, length
    if c == "next-line":
        nl = len(L[l + 1])
        return L, l + 1, col if col <= nl else nl
    if c == "prev-line":
        pl = len(L[l - 1])
        return L, l - 1, col if col <= pl else pl
    if c == "back":
        if col > 0:
            L[l] = ln[: col - 1] + ln[col:]
            return L, l, col - 1
        pv = L[l - 1]
        L[l - 1] = pv + ln
        del L[l]
        return L, l - 1, len(pv)
    if c == "kill-line":
        if col < length:
            L[l] = ln[:col]
            return L, l, col
        L[l] = ln + L[l + 1]
        del L[l + 1]
        return L, l, col
    if c == "open-line":
        L[l] = ln[:col]
        L.insert(l + 1, ln[col:])
        return L, l, col
    return L, l, col


def sim(plan: list, goal=None):
    goal = goal or [codes(x) for x in GOAL]
    unk = unkind(plan)
    L = start_lines()
    l = col = keys = rej = 0
    for c in expand(plan):
        reason = gate(c, L, l, col)
        if reason == "ok":
            L, l, col = apply_cmd(c, L, l, col)
            keys += 1
        else:
            rej += 1
    d = dist_lines(L, goal)
    score = BASE - keys - 2 * rej - 3 * d - 4 * unk
    text = "|".join("".join(chr(c) for c in row) for row in L)
    return {
        "score": score,
        "keys": keys,
        "rejects": rej,
        "dist": d,
        "unkind": unk,
        "text": text,
    }


def card(a: int, b: int) -> str:
    if b > a:
        keep, say = "b", "b is closer"
    elif b == a:
        keep, say = "a", "same score, keeping yours"
    else:
        keep, say = "a", "a is closer"
    return f'CARD a={a} b={b} KEEP={keep} say="{say}"'


FIXTURES = {
    "main": ["kill-line", "type:hi", "open-line", "next-line", "type:au"],
    "worse": ["kill-line", "kill-line", "left", "next-line", "prev-line", "type:hi"],
    "tie": ["kill-line", "type:hi", "open-line", "next-line", "type:au"],
    "better": ["kill-line", "type:hi", "open-line", "next-line", "type:aura"],
}


def check() -> int:
    main = sim(FIXTURES["main"])
    worse = sim(FIXTURES["worse"])
    tie = sim(FIXTURES["tie"])
    better = sim(FIXTURES["better"])
    assert main["score"] == 27, main
    assert worse["score"] == 14, worse
    assert tie["score"] == 27, tie
    assert better["score"] == 31, better
    assert better["text"] == "hi|aura", better
    print(f'MAIN score={main["score"]} text={main["text"]}')
    print(f'WORSE score={worse["score"]} text={worse["text"]}')
    print(f'TIE score={tie["score"]} text={tie["text"]}')
    print(f'BETTER score={better["score"]} text={better["text"]}')
    print(card(main["score"], worse["score"]))
    print(card(main["score"], tie["score"]))
    print(card(main["score"], better["score"]))
    print("PAD_M8_MODEL_OK")
    return 0


def main(argv: list[str]) -> int:
    if argv[1:] == ["--check"]:
        return check()
    if not argv[1:]:
        print("usage: goal_model.py --check | TOKEN...", file=sys.stderr)
        return 2
    r = sim(argv[1:])
    print(
        f'score={r["score"]} keys={r["keys"]} rejects={r["rejects"]} '
        f'dist={r["dist"]} unkind={r["unkind"]} text={r["text"]}'
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
