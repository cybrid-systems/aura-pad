#!/usr/bin/env python3
"""M7 host check: Soft DIRTY lines are sound and tight.

Reads a Soft play stream (SNAP v1 pad blocks mixed with anything else).
For each pair of consecutive complete blocks with the same row count:

  sound : every row whose T/H/M text changed is listed in DIRTY
  tight : every DIRTY row either changed or is the cursor row

The first block must carry no DIRTY (C full-blits it). Blocks whose row
count changed are full blits on the C side; DIRTY must still list every
row index that differs. C never computes this -- Soft does; this script
only audits Soft's claim. Prints PAD_M7_DIRTY_OK.
"""
import sys


def blocks(text):
    cur = None
    for line in text.split("\n"):
        if line == "SNAP v1 pad":
            cur = {"dirty": None, "rows": [], "cursor": None}
            continue
        if cur is None:
            continue
        if line == "END":
            yield cur
            cur = None
        elif line.startswith("DIRTY lines="):
            cur["dirty"] = [int(x) for x in line[12:].split(",") if x]
        elif line.startswith("CURSOR line="):
            a = line.split()
            cur["cursor"] = (int(a[1][5:]), int(a[2][4:]))
        elif line[:2] in ("T ", "H ", "M "):
            if line[0] == "T":
                cur["rows"].append([line[2:]])
            else:
                cur["rows"][-1].append(line[2:])


def main(path):
    bs = list(blocks(open(path).read()))
    if len(bs) < 2:
        print("PAD_M7_DIRTY_FAIL reason=too-few-blocks n=%d" % len(bs))
        return 1
    if bs[0]["dirty"] is not None:
        print("PAD_M7_DIRTY_FAIL reason=first-block-has-dirty")
        return 1
    pairs = sound = tight = partial = 0
    for i in range(1, len(bs)):
        a, b = bs[i - 1], bs[i]
        d = b["dirty"]
        if d is None:
            print("PAD_M7_DIRTY_FAIL reason=missing-dirty block=%d" % i)
            return 1
        n = len(b["rows"])
        changed = {r for r in range(n)
                   if r >= len(a["rows"]) or a["rows"][r] != b["rows"][r]}
        cur = b["cursor"][0]
        miss = changed - set(d)
        extra = set(d) - changed - {cur}
        if miss:
            print("PAD_M7_DIRTY_FAIL reason=unsound block=%d missing=%s" % (i, sorted(miss)))
            return 1
        if extra:
            print("PAD_M7_DIRTY_FAIL reason=loose block=%d extra=%s" % (i, sorted(extra)))
            return 1
        if d != sorted(d):
            print("PAD_M7_DIRTY_FAIL reason=unsorted block=%d" % i)
            return 1
        pairs += 1
        sound += 1
        tight += 1
        if len(d) < n:
            partial += 1
    print("M7_DIRTY blocks=%d pairs=%d partial=%d" % (len(bs), pairs, partial))
    print("PAD_M7_DIRTY_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
