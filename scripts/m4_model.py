#!/usr/bin/env python3
"""Python model of the Soft M4 pad (soft/pad/m4.aura): two named pads,
find / find-next / replace / replace-all, record / stop / play macros,
and the buffer law (wrap max).

Independent re-implementation used to cross-check Soft numbers. Builds on
edit_model.py (the M3.5 editor). Pure host code, no HTTP, no Soft.
`m4_model.py --check` prints PAD_M4_MODEL_OK when the model re-computes the
same numbers that soft/pad/m4_test.aura asserts: start distance / score,
every fixture score (FX_*), the three law scores, and the view + reject
count of every row in the Soft plan table (which must list exactly PLANS).
`m4_model.py TOKEN...` prints the score breakdown of one story macro
(law wrap-3).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import edit_model as em  # noqa: E402

MAX_COL = em.MAX_COL
MACRO_MAX = 12
BASE4 = 60
STORY0 = ["a cat", "the cat ran"]
SCRATCH0 = ["my notes", "they had fun"]
GOAL_STORY = ["a dog", "the dog ran", "they had fun"]
GOAL_SCRATCH = ["my notes", "they had fun"]
NAMES = ["story", "scratch"]
LAW_MAIN = (0, 3)     # (wrap, max replace-all spots)
LAW_WRAP = (1, 3)
LAW_BIG = (1, 9)
MEAN = ("stupid", "dumb", "hate", "idiot", "shut up")
LAW_KEYS = ["replace-all:a=o", "eob", "find:cat", "replace:dog",
            "find-next", "replace:dog"]


class Ms:
    def __init__(self, bufs, cur="story", needle="", rec=0, macro=None, law=LAW_MAIN):
        self.bufs = dict(bufs)
        self.cur = cur
        self.needle = needle
        self.rec = rec
        self.macro = list(macro or [])
        self.law = law

    def copy(self, **kw):
        d = dict(bufs=self.bufs, cur=self.cur, needle=self.needle, rec=self.rec,
                 macro=self.macro, law=self.law)
        d.update(kw)
        return Ms(**d)

    @property
    def st(self) -> em.St:
        return self.bufs[self.cur]

    def view(self) -> str:
        v = self.st.view()
        other = [n for n in NAMES if n != self.cur][0]
        ot = "|".join(x.replace(" ", ".") for x in self.bufs[other].L)
        nd = self.needle.replace(" ", ".") if self.needle else "none"
        return (f"{self.cur}:{v} {other}={ot} find={nd} "
                f"rec={'on' if self.rec else 'off'} macro={len(self.macro)}")


def start(law=LAW_MAIN) -> Ms:
    return Ms({"story": em.St(STORY0), "scratch": em.St(SCRATCH0)}, law=law)


def printable(t: str) -> bool:
    return all(c == " " or "a" <= c <= "z" for c in t)


def mean_word(t: str) -> str:
    for w in MEAN:
        if w in t:
            return w
    return ""


def search(L, t, l, col, wrap):
    for i in range(l, len(L)):
        j = L[i].find(t, col if i == l else 0)
        if j >= 0:
            return (i, j)
    if wrap:
        for i in range(len(L)):
            j = L[i].find(t)
            if j >= 0:
                return (i, j)
    return None


def split_rep(c: str, pre: str):
    body = c[len(pre):]
    if "=" not in body:
        return None
    a, _, b = body.partition("=")
    return a, b


def own_gate(c, ms: Ms) -> str:
    s = ms.st
    L, l, col = s.L, s.l, s.col
    if isinstance(c, str):
        if c.startswith("find:"):
            t = c[5:]
            if t == "":
                return "empty-needle"
            if not printable(t):
                return "not-print"
            return "ok" if search(L, t, l, col, ms.law[0]) else "not-found"
        if c == "find-next":
            if ms.needle == "":
                return "empty-needle"
            return "ok" if search(L, ms.needle, l, col + 1, ms.law[0]) else "not-found"
        if c.startswith("replace:"):
            new = c[8:]
            if ms.needle == "":
                return "empty-needle"
            if not printable(new):
                return "not-print"
            if mean_word(new):
                return "not-kind"
            ln = L[l]
            if ln[col:col + len(ms.needle)] != ms.needle:
                return "not-found"
            if len(ln) - len(ms.needle) + len(new) > MAX_COL:
                return "need-space"
            return "ok"
        if c.startswith("replace-all:"):
            pr = split_rep(c, "replace-all:")
            if pr is None:
                return "not-a-key"
            old, new = pr
            if old == "":
                return "empty-needle"
            if not (printable(old) and printable(new)):
                return "not-print"
            if mean_word(new):
                return "not-kind"
            n = sum(x.count(old) for x in L)
            if n == 0:
                return "not-found"
            if n > ms.law[1]:
                return "too-many"
            if any(len(x.replace(old, new)) > MAX_COL for x in L):
                return "need-space"
            return "ok"
        if c.startswith("switch:"):
            name = c[7:]
            if name not in ms.bufs:
                return "no-buffer"
            return "already-there" if name == ms.cur else "ok"
        if c == "rec":
            return "busy-recording" if ms.rec else "ok"
        if c == "stop":
            if not ms.rec:
                return "not-recording"
            return "empty-macro" if not ms.macro else "ok"
        if c == "play":
            if ms.rec:
                return "busy-recording"
            return "no-macro" if not ms.macro else "ok"
    return em.egate(c, s)


def m4gate(c, ms: Ms) -> str:
    why = own_gate(c, ms)
    if why != "ok":
        return why
    if ms.rec and c not in ("rec", "stop", "play") and len(ms.macro) >= MACRO_MAX:
        return "macro-full"
    return "ok"


def put(ms: Ms, st: em.St) -> Ms:
    b = dict(ms.bufs)
    b[ms.cur] = st
    return ms.copy(bufs=b)


def apply1(c, ms: Ms) -> Ms:
    s = ms.st
    L, l, col = s.L, s.l, s.col
    if isinstance(c, str):
        if c.startswith("find:"):
            t = c[5:]
            i, j = search(L, t, l, col, ms.law[0])
            return put(ms, em.St(L, i, j, s.kill, s.mark, s.undo)).copy(needle=t)
        if c == "find-next":
            i, j = search(L, ms.needle, l, col + 1, ms.law[0])
            return put(ms, em.St(L, i, j, s.kill, s.mark, s.undo))
        if c.startswith("replace:"):
            new = c[8:]
            ln = L[l]
            L2 = list(L)
            L2[l] = ln[:col] + new + ln[col + len(ms.needle):]
            return put(ms, em.edit(s, (L2, l, col + len(new)), s.kill))
        if c.startswith("replace-all:"):
            old, new = split_rep(c, "replace-all:")
            L2 = [x.replace(old, new) for x in L]
            return put(ms, em.edit(s, (L2, l, min(col, len(L2[l]))), s.kill))
        if c.startswith("switch:"):
            name = c[7:]
            t = ms.bufs[name]
            b = dict(ms.bufs)
            b[name] = em.St(t.L, t.l, t.col, s.kill, t.mark, t.undo)
            return ms.copy(bufs=b, cur=name)
        if c == "rec":
            return ms.copy(rec=1, macro=[])
        if c == "stop":
            return ms.copy(rec=0)
    return put(ms, em.eapply(c, s))


def step(c, ms: Ms):
    """One token: (ms, keys, rejects, reason)."""
    why = m4gate(c, ms)
    if why != "ok":
        return ms, 0, 1, why
    if c == "play":
        inner = 0
        for t in ms.macro:
            ms2, _k, r, _w = step(t, ms)
            ms, inner = ms2, inner + r
        return ms, 1, inner, "ok"
    ms2 = apply1(c, ms)
    if ms.rec and c not in ("rec", "stop", "play"):
        ms2 = ms2.copy(macro=ms2.macro + [c])
    return ms2, 1, 0, "ok"


def play_from(ms: Ms, plan):
    keys = rej = 0
    rejects = []
    for i, c in enumerate(em.expand(plan), 1):
        ms, k, r, why = step(c, ms)
        keys += k
        rej += r
        if why != "ok":
            rejects.append((i, c, why))
    return ms, keys, rej, rejects


def dist4(ms: Ms) -> int:
    return (em.dist_lines(ms.bufs["story"].L, GOAL_STORY)
            + em.dist_lines(ms.bufs["scratch"].L, GOAL_SCRATCH))


def msim(plan, law=LAW_MAIN):
    ms, keys, rej, rejects = play_from(start(law), plan)
    d = dist4(ms)
    return {"score": BASE4 - keys - 2 * rej - 3 * d, "keys": keys, "rej": rej,
            "dist": d, "view": ms.view(), "rejects": rejects}


def read_lambda(path: Path):
    text = path.read_text()
    m = re.fullmatch(r"\s*\(lambda \(\) \(list (.*)\)\)\s*", text, re.S)
    if not m:
        return None
    toks = re.findall(r'"([^"]*)"|(-?\d+)|(#t|#f)', m.group(1))
    out = []
    for a, b, c in toks:
        if c:
            return None
        out.append(a if a or not b else int(b))
    return out


# Plan table shared with soft/pad/m4_test.aura: (name, law, plan).
PLANS = [
    ("find_ok", LAW_MAIN, ["find:cat"]),
    ("find_empty", LAW_MAIN, ["find:"]),
    ("find_missing", LAW_MAIN, ["find:cow"]),
    ("find_caps", LAW_MAIN, ["find:Cat"]),
    ("find_line2", LAW_MAIN, ["find:ran"]),
    ("find_next", LAW_MAIN, ["find:cat", "find-next"]),
    ("find_next_end", LAW_MAIN, ["find:cat", "find-next", "find-next"]),
    ("find_next_none", LAW_MAIN, ["find-next"]),
    ("find_nowrap", LAW_MAIN, ["eob", "find:cat"]),
    ("find_wrap", LAW_WRAP, ["eob", "find:cat"]),
    ("next_wrap", LAW_WRAP, ["find:cat", "find-next", "find-next"]),
    ("replace_one", LAW_MAIN, ["find:cat", "replace:dog"]),
    ("replace_none", LAW_MAIN, ["replace:dog"]),
    ("replace_moved", LAW_MAIN, ["find:cat", "right", "replace:dog"]),
    ("replace_mean", LAW_MAIN, ["find:cat", "replace:dumb"]),
    ("replace_full", LAW_MAIN, ["find:ran", "replace:far far"]),
    ("replace_undo", LAW_MAIN, ["find:cat", "replace:dog", "undo"]),
    ("replace_two", LAW_MAIN, ["find:cat", "replace:dog", "find-next", "replace:dog"]),
    ("all_ok", LAW_MAIN, ["replace-all:cat=dog"]),
    ("all_empty", LAW_MAIN, ["replace-all:=dog"]),
    ("all_noeq", LAW_MAIN, ["replace-all:cat"]),
    ("all_missing", LAW_MAIN, ["replace-all:cow=dog"]),
    ("all_many", LAW_MAIN, ["replace-all:a=o"]),
    ("all_big", LAW_BIG, ["replace-all:a=o"]),
    ("all_full", LAW_MAIN, ["replace-all:ran=rocket"]),
    ("all_mean", LAW_MAIN, ["replace-all:cat=idiot"]),
    ("all_undo", LAW_MAIN, ["replace-all:cat=dog", "undo"]),
    ("switch_ok", LAW_MAIN, ["switch:scratch"]),
    ("switch_same", LAW_MAIN, ["switch:story"]),
    ("switch_zoo", LAW_MAIN, ["switch:zoo"]),
    ("switch_back", LAW_MAIN, ["switch:scratch", "eob", "switch:story"]),
    ("switch_kill", LAW_MAIN, ["switch:scratch", "kill-line", "switch:story", "yank"]),
    ("switch_yank", LAW_MAIN, ["switch:scratch", "eob", "set-mark", "left", "left", "left",
                               "copy-region", "switch:story", "end", "yank"]),
    ("switch_find", LAW_MAIN, ["find:cat", "switch:scratch", "find-next"]),
    ("rec_play", LAW_MAIN, ["rec", "type:ab", "stop", "play"]),
    ("rec_twice", LAW_MAIN, ["rec", "rec"]),
    ("stop_none", LAW_MAIN, ["stop"]),
    ("stop_empty", LAW_MAIN, ["rec", "stop"]),
    ("play_none", LAW_MAIN, ["play"]),
    ("play_busy", LAW_MAIN, ["rec", "right", "play"]),
    ("rec_reject", LAW_MAIN, ["rec", "left", "right", "stop", "play"]),
    ("rec_full", LAW_MAIN, ["rec"] + ["end", "home"] * 7 + ["stop"]),
    ("play_oops", LAW_MAIN, ["find:cat", "rec", "replace:dog", "find-next", "stop", "play"]),
    ("play_switch", LAW_MAIN, ["rec", "switch:scratch", "stop", "play"]),
    ("law_main", LAW_MAIN, LAW_KEYS),
    ("law_wrap", LAW_WRAP, LAW_KEYS),
    ("law_big", LAW_BIG, LAW_KEYS),
]


LAWS = {"law-main": LAW_MAIN, "law-wrap": LAW_WRAP, "law-big": LAW_BIG}


def parse_tok(t: str):
    t = t.strip()
    return int(t) if re.fullmatch(r"-?\d+", t) else t.strip('"')


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    if len(sys.argv) > 1 and sys.argv[1] != "--check":
        plan = [int(t) if t.isdigit() else t for t in sys.argv[1:]]
        print(json.dumps(msim(plan, LAW_WRAP)))
        return 0
    # The Soft test file is the single source of expected numbers: the
    # model re-computes every one of them independently.
    soft = (root / "soft/pad/m4_test.aura").read_text()
    bad = 0

    def check(tag, got, want):
        nonlocal bad
        ok = got == want
        print(f"M4MODEL {tag} got={got} {'OK' if ok else 'BAD want=' + str(want)}")
        bad += 0 if ok else 1

    num = dict((k, int(v)) for k, v in re.findall(r'\(expect "(\w+)" [^\n]* (-?\d+)\)+\s*$', soft, re.M))
    check("START_DIST", dist4(start()), num.get("START_DIST"))
    check("START_SCORE", msim([])["score"], num.get("START_SCORE"))
    fx = dict(re.findall(r'\(expect "(FX_\w+)" \(fx-score "([\w.]+)"\)', soft))
    for tag, name in sorted(fx.items()):
        plan = read_lambda(root / "soft/pad/fixtures/m4" / name)
        check(tag, msim(plan, LAW_WRAP)["score"], num.get(tag))
    for tag, law in (("LAW_MAIN_SCORE", LAW_MAIN), ("LAW_WRAP_SCORE", LAW_WRAP),
                     ("LAW_BIG_SCORE", LAW_BIG)):
        check(tag, msim(LAW_KEYS, law)["score"], num.get(tag))
    rows = re.findall(r'\(row "(\w+)" (law-\w+) \(list ([^\n]*)\)\s+"([^"]*)" (\d+)\)', soft)
    for name, law, plan_s, view, rej in rows:
        plan = [parse_tok(t) for t in re.findall(r'"[^"]*"|-?\d+', plan_s)]
        ms, _k, r, _x = play_from(start(LAWS[law]), plan)
        ok = ms.view() == view and r == int(rej)
        print(f"M4MODEL plan={name} view={ms.view()} rej={r} {'OK' if ok else 'BAD want=' + view}")
        bad += 0 if ok else 1
    # Every model plan must be in the Soft table (and nothing extra).
    names = [r[0] for r in rows]
    check("PLAN_TABLE", names, [p[0] for p in PLANS])
    print("PAD_M4_MODEL_OK" if bad == 0 else f"PAD_M4_MODEL_FAIL bad={bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
