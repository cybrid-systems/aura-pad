#!/usr/bin/env python3
"""Byte-oracle for one M14 multi-window SNAP.

Soft already chose the rectangles. This checks they tile the bounding
box once, exactly one window is selected, and each T row is the width
Soft declared. Prints PAD_M14_MODEL_OK.
"""
import sys

def fail(msg):
    print("PAD_M14_MODEL_FAIL " + msg)
    sys.exit(1)

def main():
    path = sys.argv[1]
    lines = open(path).read().splitlines()
    if not lines or lines[0] != "SNAP v1 pad":
        fail("not a v1 snap")
    if lines[-1] != "END":
        fail("no END")
    try:
        i = lines.index(next(x for x in lines if x.startswith("WINS n=")))
    except StopIteration:
        fail("no WINS")
    n = int(lines[i].split("=", 1)[1])
    if n < 2:
        fail("need two windows")
    i += 1
    wins = []
    for _ in range(n):
        if i >= len(lines) or not lines[i].startswith("WIN "):
            fail("missing WIN")
        fields = {}
        for part in lines[i][4:].split():
            k, v = part.split("=", 1)
            fields[k] = int(v)
        for key in ("r", "c", "h", "w", "sel", "cy", "cx"):
            if key not in fields:
                fail("WIN missing " + key)
        i += 1
        rows = []
        for _r in range(fields["h"]):
            if i + 2 >= len(lines):
                fail("short window")
            t, h, m = lines[i], lines[i + 1], lines[i + 2]
            if not (t.startswith("T ") and h.startswith("H ") and m.startswith("M ")):
                fail("row tags")
            if not (len(t) - 2 == fields["w"] == len(h) - 2 == len(m) - 2):
                fail("width %d want %d" % (len(t) - 2, fields["w"]))
            rows.append(t[2:])
            i += 3
        if fields["cy"] < 0 or fields["cy"] >= fields["h"]:
            fail("cursor row")
        if fields["cx"] < 0 or fields["cx"] > fields["w"]:
            fail("cursor col")
        wins.append(fields)
    sel = [w for w in wins if w["sel"] == 1]
    if len(sel) != 1:
        fail("sel %d" % len(sel))
    H = max(w["r"] + w["h"] for w in wins)
    W = max(w["c"] + w["w"] for w in wins)
    cover = [[0] * W for _ in range(H)]
    for w in wins:
        for y in range(w["r"], w["r"] + w["h"]):
            for x in range(w["c"], w["c"] + w["w"]):
                if y < 0 or x < 0 or y >= H or x >= W:
                    fail("outside")
                cover[y][x] += 1
    for row in cover:
        for cell in row:
            if cell != 1:
                fail("not a tiling")
    print("PAD_M14_MODEL_OK wins=%d box=%dx%d" % (n, H, W))

if __name__ == "__main__":
    main()
