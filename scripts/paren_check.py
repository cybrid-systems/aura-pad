#!/usr/bin/env python3
"""Paren balance check for Soft (.aura) files.

The tip loader silently stops reading a file at an unbalanced ")" (Aura
#4342), so smoke runs this first. Skips ; comments, "strings" (with \\
escapes) and #\\x char literals. Exit 1 with file:line on the first problem.
"""
import sys


def check(path: str) -> str | None:
    text = open(path, encoding="utf-8").read()
    depth = 0
    i = 0
    line = 1
    opened: list[int] = []
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
        elif c == ";":
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif c == '"':
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    i += 1
                elif text[i] == "\n":
                    line += 1
                i += 1
        elif c == "#" and i + 1 < n and text[i + 1] == "\\":
            i += 3
            while i < n and text[i].isalpha():
                i += 1
            continue
        elif c == "(":
            depth += 1
            opened.append(line)
        elif c == ")":
            depth -= 1
            if depth < 0:
                return f"{path}:{line}: unbalanced ')'"
            opened.pop()
        i += 1
    if depth != 0:
        return f"{path}:{opened[-1]}: unclosed '(' (depth {depth} at EOF)"
    return None


def main() -> int:
    bad = 0
    for p in sys.argv[1:]:
        err = check(p)
        if err:
            print("PAREN_FAIL " + err)
            bad += 1
    if bad == 0:
        print(f"PAREN_OK files={len(sys.argv) - 1}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
