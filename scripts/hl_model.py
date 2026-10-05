#!/usr/bin/env python3
"""Host model of M5 Soft HL tokenize + jump/refs (cross-check for m5_test.aura)."""
from __future__ import annotations

import sys

KEYWORDS = {
    "define", "lambda", "if", "load", "cond", "let", "begin",
    "set!", "and", "or", "not", "else", "require", "export",
    "try", "catch", "list", "cons", "car", "cdr", "null?",
    "string=?", "number?", "string?", "display", "newline",
}

SYM = set(
    b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    b"-_:+*/=?! .<>$%&^~"
)
# note: space intentionally not in SYM; handled separately
SYM = set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    "-_:+*/=?! .<>$%&^~".replace(" ", "")
)


def kind_of(name: str) -> str:
    if name.startswith("query:"):
        return "Q"
    if name.startswith("mutate:"):
        return "M"
    if name in KEYWORDS:
        return "K"
    return "S"


def tokenize(s: str) -> list[tuple[str, int, int, str]]:
    n = len(s)
    i = 0
    out: list[tuple[str, int, int, str]] = []
    while i < n:
        c = s[i]
        if c in "()":
            out.append(("P", i, i + 1, c))
            i += 1
        elif c == ";":
            j = i + 1
            while j < n and s[j] != "\n":
                j += 1
            out.append(("C", i, j, s[i:j]))
            i = j
        elif c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\":
                    j = n if j + 1 >= n else j + 2
                    continue
                if s[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(("T", i, j, s[i:j]))
            i = j
        elif c in " \t\n\r":
            j = i + 1
            while j < n and s[j] in " \t\n\r":
                j += 1
            i = j  # skip space
        elif c.isdigit() and (i == 0 or s[i - 1] in " \t\n\r()"):
            j = i + 1
            while j < n and s[j].isdigit():
                j += 1
            out.append(("N", i, j, s[i:j]))
            i = j
        elif c in SYM:
            j = i + 1
            while j < n and s[j] in SYM:
                j += 1
            txt = s[i:j]
            out.append((kind_of(txt), i, j, txt))
            i = j
        else:
            i += 1
    return out


def color(s: str) -> str:
    # rebuild via same rules, including spaces
    n = len(s)
    i = 0
    chars: list[str] = []
    while i < n:
        c = s[i]
        if c in "()":
            chars.append("P")
            i += 1
        elif c == ";":
            j = i + 1
            while j < n and s[j] != "\n":
                j += 1
            chars.extend("C" * (j - i))
            i = j
        elif c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\":
                    j = n if j + 1 >= n else j + 2
                    continue
                if s[j] == '"':
                    j += 1
                    break
                j += 1
            chars.extend("T" * (j - i))
            i = j
        elif c in " \t\n\r":
            j = i + 1
            while j < n and s[j] in " \t\n\r":
                j += 1
            chars.extend("." * (j - i))
            i = j
        elif c.isdigit() and (i == 0 or s[i - 1] in " \t\n\r()"):
            j = i + 1
            while j < n and s[j].isdigit():
                j += 1
            chars.extend("N" * (j - i))
            i = j
        elif c in SYM:
            j = i + 1
            while j < n and s[j] in SYM:
                j += 1
            letter = kind_of(s[i:j])
            chars.extend(letter * (j - i))
            i = j
        else:
            chars.append(".")
            i += 1
    return "".join(chars)


def is_def_name(tokens: list[tuple[str, int, int, str]], idx: int, name: str) -> bool:
    k, a, b, txt = tokens[idx]
    if txt != name:
        return False
    if idx == 0:
        return False
    prev = tokens[idx - 1]
    if prev[0] == "K" and prev[3] == "define":
        return True
    if prev[0] == "P" and idx >= 2:
        prev2 = tokens[idx - 2]
        if prev2[0] == "K" and prev2[3] == "define":
            return True
    return False


def find_defs(s: str, name: str) -> list[int]:
    ts = tokenize(s)
    return [ts[i][1] for i in range(len(ts)) if is_def_name(ts, i, name)]


def find_refs(s: str, name: str) -> list[int]:
    return [a for k, a, b, txt in tokenize(s) if txt == name and k in "SKQM"]


FIXTURE = (
    '(define (hello x) (+ x 1))\n'
    '(define (bye y) (hello y))\n'
    '(hello 3)\n'
    '; comment\n'
    '(query:find "hello")\n'
    '(mutate:summary)\n'
)

HL_DEMO = '(define (foo x) ; hi\n  (+ x 1))\n(query:find "foo")\n(mutate:summary)'


def check() -> int:
    toks = tokenize(HL_DEMO)
    col = color(HL_DEMO)
    assert len(HL_DEMO) == len(col), (len(HL_DEMO), len(col))
    counts = {k: sum(1 for t in toks if t[0] == k) for k in "PKSTCQMN"}
    # Soft probe expected
    soft_color = (
        "PKKKKKK.PSSS.SP.CCCC...PS.S.NPP.PQQQQQQQQQQ.TTTTTP.PMMMMMMMMMMMMMMP"
    )
    if col != soft_color:
        print("HL_COLOR_FAIL")
        print("want", soft_color)
        print("got ", col)
        return 1
    print(f"HL_MODEL color_ok n={len(HL_DEMO)} toks={len(toks)} "
          f"K={counts['K']} Q={counts['Q']} M={counts['M']} "
          f"C={counts['C']} T={counts['T']}")

    refs_hello = find_refs(FIXTURE, "hello")
    defs_hello = find_defs(FIXTURE, "hello")
    refs_bye = find_refs(FIXTURE, "bye")
    defs_plus = find_defs(FIXTURE, "+")
    print(f"JUMP_MODEL defs_hello={'.'.join(map(str, defs_hello))} "
          f"refs_hello={'.'.join(map(str, refs_hello))} "
          f"defs_bye={'.'.join(map(str, find_defs(FIXTURE, 'bye')))} "
          f"refs_bye={'.'.join(map(str, refs_bye))} "
          f"defs_plus={len(defs_plus)}")

    # Numbers Soft m5_test.aura asserts (keep in sync)
    expect = {
        "HL_N": len(HL_DEMO),
        "HL_TOKS": len(toks),
        "HL_K": counts["K"],
        "HL_Q": counts["Q"],
        "HL_M": counts["M"],
        "HL_C": counts["C"],
        "HL_T": counts["T"],
        "DEF_HELLO": defs_hello[0] if defs_hello else -1,
        "REF_HELLO_N": len(refs_hello),
        "REF_HELLO_0": refs_hello[0],
        "REF_HELLO_1": refs_hello[1],
        "REF_HELLO_2": refs_hello[2],
        "DEF_BYE": find_defs(FIXTURE, "bye")[0],
    }
    for k, v in expect.items():
        print(f"EXPECT {k}={v}")
    print("PAD_M5_MODEL_OK")
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--check":
        return check()
    if len(sys.argv) > 1:
        s = sys.argv[1]
        print(color(s))
        for t in tokenize(s):
            print(t)
        return 0
    return check()


if __name__ == "__main__":
    sys.exit(main())
