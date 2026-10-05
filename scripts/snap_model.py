#!/usr/bin/env python3
"""Host model of the M6 Soft SNAP packer (soft/pad/view.aura).

Rebuilds the SNAP block Soft writes for the m6_smoke fixture from the M5
host HL/jump model (hl_model.py) and compares it byte for byte with the
file Soft wrote. This checks the Soft packer, not the C viewport (C has no
logic to model: it maps letters to colors).

  snap_model.py --check [out/m6.snap]   -> PAD_M6_MODEL_OK
  snap_model.py --emit                  -> print the model block
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hl_model as hm  # noqa: E402

LEGEND = ("K=magic-word S=name T=quote C=note N=number P=paren Q=ask "
          "M=change d=born-here r=used-here")
SRC = "(define (hello x) (+ x 1)) ; hi\n(define (bye y) (hello y))\n(hello 3)"


def sym_at(s: str, point: int) -> str:
    for kind, a, b, txt in hm.tokenize(s):
        if kind in ("S", "K", "Q", "M") and a <= point < b:
            return txt
    return ""


def marks(s: str, point: int) -> str:
    out = ["."] * len(s)
    name = sym_at(s, point)
    if not name:
        return "".join(out)
    defs = set(hm.find_defs(s, name))
    for r in hm.find_refs(s, name):
        for i in range(r, min(r + len(name), len(s))):
            out[i] = "d" if r in defs else "r"
    return "".join(out)


def point_of(lines: list[str], line: int, col: int) -> int:
    return sum(len(x) + 1 for x in lines[:line]) + col


def snap(title: str, src: str, line: int, col: int, say: str) -> str:
    lines = src.split("\n")
    tape = hm.color(src)
    mk = marks(src, point_of(lines, line, col))
    out = ["SNAP v1 pad", f"TITLE {title}", f"CURSOR line={line} col={col}",
           f"SAY {say}", f"LEGEND {LEGEND}", f"ROWS n={len(lines)}"]
    off = 0
    for ln in lines:
        e = off + len(ln)
        out += [f"T {ln}", f"H {tape[off:e]}", f"M {mk[off:e]}"]
        off = e + 1
    out.append("END")
    return "\n".join(out) + "\n"


def model_first() -> str:
    return snap("kid pad (Soft)", SRC, 2, 1, "there is no line there")


def check(path: str) -> int:
    want = model_first()
    fail = 0

    def ok(tag: str, cond: bool) -> None:
        nonlocal fail
        print(f"M {tag} {'OK' if cond else 'FAIL'}")
        if not cond:
            fail += 1

    ok("TAPE_LEN", len(hm.color(SRC)) == len(SRC))
    ok("MARKS", marks(SRC, 60) ==
       ".........ddddd...................................rrrrr......rrrrr...")
    ok("POINT", point_of(SRC.split("\n"), 2, 1) == 60)
    try:
        with open(path, encoding="utf-8") as f:
            got = f.read()
    except OSError as e:
        print(f"M FILE FAIL {e}")
        return 1
    ok("BYTES", got == want)
    if got != want:
        for i, (a, b) in enumerate(zip(got.split("\n"), want.split("\n"))):
            if a != b:
                print(f"  line {i}: got={a!r} want={b!r}")
    if fail:
        print(f"PAD_M6_MODEL_FAIL fail={fail}")
        return 1
    print("PAD_M6_MODEL_OK")
    return 0


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "--emit":
        sys.stdout.write(model_first())
        return 0
    if len(sys.argv) >= 2 and sys.argv[1] == "--check":
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "out", "m6.snap")
        return check(path)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
