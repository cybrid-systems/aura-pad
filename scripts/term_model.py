#!/usr/bin/env python3
"""Tiny terminal model to check the C tty update path (c/snap.c).

Plays two byte streams written by `pad_view --replay` (cell diff, what
pad_play writes on a terminal) and `pad_view --replay-full` (full repaint
per frame) into a model screen and checks that after every frame
(ESC ] pad-frame BEL) both screens hold the same cells (letter + SGR
attributes) and the same cursor position. Understands exactly what
snap.c emits: printable bytes, \\n (pty ONLCR: CR LF), \\r, CSI H J K L M
r m, OSC ... BEL. Anything else fails loudly.

Usage: term_model.py DIFF FULL [--rows 64 --cols 240]
Prints TERM_MODEL_OK frames=N diff_bytes=.. full_bytes=.. and per-frame
medians; exit 1 on the first frame where the screens differ."""
import statistics, sys

class Screen:
    def __init__(self, rows, cols):
        self.R, self.C = rows, cols
        self.blank = (" ", ())
        self.g = [[self.blank] * cols for _ in range(rows)]
        self.y = self.x = 0
        self.top, self.bot = 0, rows - 1
        self.attr = {}

    def a(self):
        return tuple(sorted(self.attr.items()))

    def sgr(self, ps):
        if not ps:
            ps = [0]
        for p in ps:
            if p == 0: self.attr = {}
            elif p == 1: self.attr["b"] = 1
            elif p == 2: self.attr["d"] = 1
            elif p == 4: self.attr["u"] = 1
            elif p == 7: self.attr["r"] = 1
            elif p == 22: self.attr.pop("b", None); self.attr.pop("d", None)
            elif p == 24: self.attr.pop("u", None)
            elif p == 27: self.attr.pop("r", None)
            elif 30 <= p <= 37 or 90 <= p <= 97: self.attr["fg"] = p
            elif p == 39: self.attr.pop("fg", None)
            elif 40 <= p <= 47 or 100 <= p <= 107: self.attr["bg"] = p
            elif p == 49: self.attr.pop("bg", None)
            else: raise ValueError(f"SGR {p}")

    def lf(self):
        if self.y == self.bot:
            del self.g[self.top]
            self.g.insert(self.bot, [self.blank] * self.C)
        elif self.y < self.R - 1:
            self.y += 1

    def csi(self, ps, f):
        n = ps[0] if ps and ps[0] else 1
        if f in "Hf":
            self.y = min(self.R - 1, (ps[0] if len(ps) > 0 and ps[0] else 1) - 1)
            self.x = min(self.C - 1, (ps[1] if len(ps) > 1 and ps[1] else 1) - 1)
        elif f == "J":
            m = ps[0] if ps else 0
            if m == 2:
                self.g = [[self.blank] * self.C for _ in range(self.R)]
            elif m == 0:
                self.g[self.y][self.x:] = [self.blank] * (self.C - self.x)
                for r in range(self.y + 1, self.R):
                    self.g[r] = [self.blank] * self.C
            else: raise ValueError(f"J{m}")
        elif f == "K":
            m = ps[0] if ps else 0
            if m == 2: self.g[self.y] = [self.blank] * self.C
            elif m == 0: self.g[self.y][self.x:] = [self.blank] * (self.C - self.x)
            else: raise ValueError(f"K{m}")
        elif f in "LM":
            if self.top <= self.y <= self.bot:
                for _ in range(n):
                    if f == "L":
                        del self.g[self.bot]
                        self.g.insert(self.y, [self.blank] * self.C)
                    else:
                        del self.g[self.y]
                        self.g.insert(self.bot, [self.blank] * self.C)
                self.x = 0
        elif f == "r":
            t = (ps[0] if len(ps) > 0 and ps[0] else 1) - 1
            b = (ps[1] if len(ps) > 1 and ps[1] else self.R) - 1
            self.top, self.bot = t, min(b, self.R - 1)
            self.y = self.x = 0
        elif f == "m":
            self.sgr(ps)
        else:
            raise ValueError(f"CSI {f}")

    def feed(self, data):
        """yields at each frame marker"""
        i, n = 0, len(data)
        while i < n:
            c = data[i]
            if c == 0x1b:
                if data[i + 1] == ord("["):
                    j = i + 2
                    while not (0x40 <= data[j] <= 0x7e):
                        j += 1
                    body = data[i + 2:j].decode()
                    ps = [int(p) if p else 0 for p in body.split(";")] if body else []
                    self.csi(ps, chr(data[j]))
                    i = j + 1
                    continue
                if data[i + 1] == ord("]"):
                    j = data.index(7, i)
                    if data[i + 2:j] == b"pad-frame":
                        yield i
                    i = j + 1
                    continue
                raise ValueError(f"ESC {data[i+1]:#x} at {i}")
            if c == 10:
                self.x = 0
                self.lf()
            elif c == 13:
                self.x = 0
            elif c >= 32:
                if self.x < self.C:
                    self.g[self.y][self.x] = (chr(c), self.a())
                    self.x += 1
            else:
                raise ValueError(f"control {c:#x} at {i}")
            i += 1

    def dump(self):
        return ["".join(ch for ch, _ in row).rstrip() for row in self.g]

def main():
    args = sys.argv[1:]
    rows, cols = 64, 240
    if "--rows" in args:
        k = args.index("--rows"); rows = int(args[k + 1]); del args[k:k + 2]
    if "--cols" in args:
        k = args.index("--cols"); cols = int(args[k + 1]); del args[k:k + 2]
    d = open(args[0], "rb").read()
    f = open(args[1], "rb").read()
    sd, sf = Screen(rows, cols), Screen(rows, cols)
    gd, gf = sd.feed(d), sf.feed(f)
    frames, pd, pf, bd, bf = 0, 0, 0, [], []
    while True:
        md = next(gd, None)
        mf = next(gf, None)
        if md is None and mf is None:
            break
        if md is None or mf is None:
            print(f"TERM_MODEL_FAIL frame={frames} streams have different frame counts")
            return 1
        bd.append(md - pd); bf.append(mf - pf)
        pd, pf = md + 11, mf + 11
        if sd.g != sf.g or (sd.y, sd.x) != (sf.y, sf.x):
            print(f"TERM_MODEL_FAIL frame={frames} cursor diff={sd.y},{sd.x} full={sf.y},{sf.x}")
            for r, (a, b) in enumerate(zip(sd.g, sf.g)):
                if a != b:
                    print(f"  row {r}: diff={''.join(c for c,_ in a).rstrip()!r}")
                    print(f"  row {r}: full={''.join(c for c,_ in b).rstrip()!r}")
                    for x, (ca, cb) in enumerate(zip(a, b)):
                        if ca != cb:
                            print(f"    first cell {x}: diff={ca} full={cb}")
                            break
            return 1
        frames += 1
    rest = bd[1:] or bd
    print(f"TERM_MODEL_OK frames={frames} diff_bytes={sum(bd)} full_bytes={sum(bf)} "
          f"diff_med={statistics.median(rest):.0f} full_med={statistics.median(bf):.0f}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
