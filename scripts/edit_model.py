#!/usr/bin/env python3
"""Python model of the Soft M3/M3.5 editor (lines.aura + edit.aura).

Independent re-implementation used to cross-check Soft expectations: the
M3.5 unit test values and the goal3 helper fixture scores. Pure host code,
no HTTP, no Soft. `edit_model.py --check` prints PAD_MODEL_OK when the
goal3 start distance, every fixture score/view and every plan view in
soft/pad/fixtures/m35/expect.json match, and the plan table inside
soft/pad/m35_test.aura carries the same views. `edit_model.py PLAN...`
prints the score breakdown of one goal3 plan (tokens: words or ints).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SEED = 20261005
MAX_LINES, MAX_COL, NOISE = 4, 12, 3
UNDO_MAX, INDENT = 8, 2
LINE_CMDS = {"left", "right", "home", "end", "back", "open-line", "kill-line",
             "next-line", "prev-line"}
GOAL2 = ["hi", "aura"]
GOAL3 = ["hi", "  aura", "pad"]
BASE2, BASE3 = 40, 60


def seed_step(s: int) -> int:
    return (s * 75 + 74) % 65537


def start_lines() -> list[str]:
    r = seed_step(SEED)
    out = ""
    for _ in range(NOISE):
        out += chr(97 + r % 26)
        r = seed_step(r)
    return [out]


def dist(a: str, b: str) -> int:
    d = sum(1 for x, y in zip(a, b) if x != y)
    return d + abs(len(a) - len(b))


def dist_lines(L: list[str], G: list[str]) -> int:
    d = 0
    for i in range(max(len(L), len(G))):
        if i >= len(L):
            d += len(G[i]) + 1
        elif i >= len(G):
            d += len(L[i]) + 1
        else:
            d += dist(L[i], G[i])
    return d


class St:
    def __init__(self, L, l=0, col=0, kill=None, mark=None, undo=None):
        self.L, self.l, self.col = list(L), l, col
        self.kill = kill or []
        self.mark = mark
        self.undo = undo or []

    def view(self) -> str:
        t = "|".join(x.replace(" ", ".") for x in self.L)
        k = "|".join(x.replace(" ", ".") for x in self.kill) if self.kill else "none"
        m = f"{self.mark[0]},{self.mark[1]}" if self.mark else "none"
        return f"{t}@{self.l},{self.col} kill={k} mark={m} undo={len(self.undo)}"


def lgate(c, L, l, col) -> str:
    n, ln = len(L), L[l]
    empty = n == 1 and len(ln) == 0
    if isinstance(c, int):
        if not (c == 32 or 97 <= c <= 122):
            return "not-print"
        return "need-space" if len(ln) >= MAX_COL else "ok"
    if c not in LINE_CMDS:
        return "not-a-key"
    if c == "left" and l == 0 and col == 0:
        return "too-far"
    if c == "right" and l == n - 1 and col >= len(ln):
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
    if c == "kill-line" and col >= len(ln) and l >= n - 1:
        return "no-line"
    if c == "open-line" and n >= MAX_LINES:
        return "need-space"
    return "ok"


def lapply(c, L, l, col):
    L = list(L)
    ln = L[l]
    if isinstance(c, int):
        L[l] = ln[:col] + chr(c) + ln[col:]
        return L, l, col + 1
    if c == "left":
        return (L, l, col - 1) if col > 0 else (L, l - 1, len(L[l - 1]))
    if c == "right":
        return (L, l, col + 1) if col < len(ln) else (L, l + 1, 0)
    if c == "home":
        return L, l, 0
    if c == "end":
        return L, l, len(ln)
    if c == "next-line":
        return L, l + 1, min(col, len(L[l + 1]))
    if c == "prev-line":
        return L, l - 1, min(col, len(L[l - 1]))
    if c == "back":
        if col > 0:
            L[l] = ln[:col - 1] + ln[col:]
            return L, l, col - 1
        pl = len(L[l - 1])
        L[l - 1] = L[l - 1] + ln
        del L[l]
        return L, l - 1, pl
    if c == "kill-line":
        if col < len(ln):
            L[l] = ln[:col]
            return L, l, col
        L[l] = ln + L[l + 1]
        del L[l + 1]
        return L, l, col
    if c == "open-line":
        L[l:l + 1] = [ln[:col], ln[col:]]
        return L, l, col
    return L, l, col


def insert_segs(L, l, col, S):
    ln = L[l]
    pre, post = ln[:col], ln[col:]
    if len(S) == 1:
        L2 = list(L)
        L2[l] = pre + S[0] + post
        return L2, l, col + len(S[0])
    fresh = [pre + S[0]] + S[1:-1] + [S[-1] + post]
    return L[:l] + fresh + L[l + 1:], l + len(S) - 1, len(S[-1])


def fits(L) -> bool:
    return len(L) <= MAX_LINES and all(len(x) <= MAX_COL for x in L)


def lead(ln: str) -> int:
    return 2 if ln.startswith("  ") else (1 if ln.startswith(" ") else 0)


def bounds(mark, l, col):
    ml, mc = mark
    return (ml, mc, l, col) if (ml, mc) <= (l, col) else (l, col, ml, mc)


def region_text(L, l1, c1, l2, c2):
    if l1 == l2:
        return [L[l1][c1:c2]]
    return [L[l1][c1:]] + L[l1 + 1:l2] + [L[l2][:c2]]


def region_delete(L, l1, c1, l2, c2):
    return L[:l1] + [L[l1][:c1] + L[l2][c2:]] + L[l2 + 1:]


def egate(c, s: St) -> str:
    L, l, col = s.L, s.l, s.col
    ln = L[l]
    if not isinstance(c, str):
        return lgate(c, L, l, col)
    if c == "undo":
        return "ok" if s.undo else "nothing-to-undo"
    if c == "yank":
        if not s.kill:
            return "nothing-to-yank"
        return "ok" if fits(insert_segs(L, l, col, s.kill)[0]) else "need-space"
    if c == "indent":
        return "need-space" if len(ln) + INDENT > MAX_COL else "ok"
    if c == "dedent":
        return "no-indent" if lead(ln) == 0 else "ok"
    if c == "bob":
        return "already-there" if (l, col) == (0, 0) else "ok"
    if c == "eob":
        return "already-there" if (l, col) == (len(L) - 1, len(ln)) else "ok"
    if c == "set-mark":
        return "already-there" if s.mark == (l, col) else "ok"
    if c in ("kill-region", "copy-region"):
        if s.mark is None:
            return "no-mark"
        return "empty-region" if s.mark == (l, col) else "ok"
    return lgate(c, L, l, col)


def edit(s: St, r, kill) -> St:
    undo = ([(list(s.L), s.l, s.col)] + s.undo)[:UNDO_MAX]
    return St(r[0], r[1], r[2], kill, None, undo)


def eapply(c, s: St) -> St:
    L, l, col = s.L, s.l, s.col
    ln = L[l]
    if isinstance(c, int):
        return edit(s, lapply(c, L, l, col), s.kill)
    if c == "undo":
        sL, sl, sc = s.undo[0]
        return St(sL, sl, sc, s.kill, None, s.undo[1:])
    if c == "yank":
        return edit(s, insert_segs(L, l, col, s.kill), s.kill)
    if c == "indent":
        L2 = list(L)
        L2[l] = "  " + ln
        return edit(s, (L2, l, col + INDENT), s.kill)
    if c == "dedent":
        k = lead(ln)
        L2 = list(L)
        L2[l] = ln[k:]
        return edit(s, (L2, l, col - k if col > k else 0), s.kill)
    if c == "bob":
        return St(L, 0, 0, s.kill, s.mark, s.undo)
    if c == "eob":
        return St(L, len(L) - 1, len(L[-1]), s.kill, s.mark, s.undo)
    if c == "set-mark":
        return St(L, l, col, s.kill, (l, col), s.undo)
    if c == "kill-region":
        b = bounds(s.mark, l, col)
        return edit(s, (region_delete(L, *b), b[0], b[1]), region_text(L, *b))
    if c == "copy-region":
        return St(L, l, col, region_text(L, *bounds(s.mark, l, col)), None, s.undo)
    if c == "kill-line":
        kt = [ln[col:]] if col < len(ln) else ["", ""]
        return edit(s, lapply(c, L, l, col), kt)
    if c in ("back", "open-line"):
        return edit(s, lapply(c, L, l, col), s.kill)
    r = lapply(c, L, l, col)
    return St(L, r[1], r[2], s.kill, s.mark, s.undo)


def expand(plan):
    out = []
    for t in plan:
        if isinstance(t, str) and t.startswith("type:"):
            out += [ord(ch) for ch in t[5:]]
        else:
            out.append(t)
    return out


def esim(plan, goal=GOAL3, base=BASE3, s: St | None = None):
    s = s or St(start_lines())
    keys = rej = 0
    rejects = []
    for i, c in enumerate(expand(plan), 1):
        why = egate(c, s)
        if why == "ok":
            s = eapply(c, s)
            keys += 1
        else:
            rej += 1
            rejects.append((i, c, why))
    d = dist_lines(s.L, goal)
    return {"score": base - keys - 2 * rej - 3 * d, "keys": keys, "rej": rej,
            "dist": d, "view": s.view(), "rejects": rejects}


def read_lambda(path: Path):
    """Tokens of a fixture `(lambda () (list ...))`; None when not a plan."""
    text = path.read_text()
    m = re.fullmatch(r"\s*\(lambda \(\) \(list (.*)\)\)\s*", text, re.S)
    if not m:
        return None
    toks = re.findall(r'"([^"]*)"|(-?\d+)', m.group(1))
    return [a if a else int(b) for a, b in toks]


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] != "--check":
        plan = [int(t) if t.isdigit() else t for t in sys.argv[1:]]
        print(json.dumps(esim(plan)))
        return 0
    root = Path(__file__).resolve().parent.parent
    want = json.loads((root / "soft/pad/fixtures/m35/expect.json").read_text())
    bad = 0
    d3 = dist_lines(start_lines(), GOAL3)
    ok = d3 == want["start_dist3"]
    print(f"MODEL start={start_lines()[0]} dist3={d3} {'OK' if ok else 'BAD'}")
    bad += 0 if ok else 1
    for name, exp in want["fixtures"].items():
        plan = read_lambda(root / "soft/pad/fixtures/m35" / name)
        got = esim(plan) if plan is not None else None
        ok = got is not None and got["score"] == exp["score"] and got["view"] == exp["view"]
        print(f"MODEL fixture={name} score={got and got['score']} want={exp['score']} "
              f"{'OK' if ok else 'BAD'}")
        bad += 0 if ok else 1
    for name, exp in want["plans"].items():
        got = esim(exp["plan"])
        ok = got["view"] == exp["view"] and got["rej"] == exp["rej"]
        print(f"MODEL plan={name} view={got['view']} rej={got['rej']} "
              f"{'OK' if ok else 'BAD want=' + exp['view']}")
        bad += 0 if ok else 1
    # The Soft unit test carries the same plan table; keep them in step.
    soft = (root / "soft/pad/m35_test.aura").read_text()
    rows = dict(re.findall(r'\(list "(\w+)" \(list [^\n]*\)\s+"([^"]*)" \d+\)', soft))
    same = rows == {k: v["view"] for k, v in want["plans"].items()}
    print(f"MODEL soft_table rows={len(rows)} plans={len(want['plans'])} "
          f"{'OK' if same else 'BAD'}")
    bad += 0 if same else 1
    print("PAD_MODEL_OK" if bad == 0 else f"PAD_MODEL_FAIL bad={bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
