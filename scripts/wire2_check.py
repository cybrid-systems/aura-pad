#!/usr/bin/env python3
"""Wire v2 oracle: a SNAP v2 stream rebuilds to the same frames as v1.

Usage: wire2_check.py V1_STREAM V2_STREAM [--view PAD_VIEW] [--out DIR]
                      [--min-frames N] [--min-v2 N]

V1_STREAM and V2_STREAM are Soft play outputs for the same keys, without
and with the "WIRE 2" offer. This script rebuilds every SNAP v2 block on
its own (independent of c/snap.c): a delta (GEN g base=b) takes the rows
it does not carry from frame b, which must be the frame just before it;
a full frame (base=-) carries every row; body= must equal the v1 ROWS
body length. Any miss fails here (Soft wrote a frame C must drop).

The v2 stream has extra full frames that Soft writes on request ("WIRE 2"
handshake, "WIRE 2 FULL", "WIRE 1"): a full frame (v2 base=-, or v1
without DIRTY) equal to the frame before it.
After dropping those, the rebuilt frames must equal the v1 frames one for
one (TITLE, CURSOR, SAY, LEGEND, rows). With --view, the C side is held
to the same: pad_view --replay-full writes the same bytes for every
matching frame of both streams, pad_view --stats reports rejected=0, and
the v2 cell-diff replay keeps a model terminal equal to the full replay
(scripts/term_model.py). OUT/v2_rebuilt.txt is the rebuilt stream in v1
form (DIRTY = rows sent), for scripts/dirty_check.py.

Prints WIRE2_CHECK_OK frames=.. v2=.. bytes_med v1/v2, lines_med v1/v2.
"""
import os, statistics, subprocess, sys

HEAD = ("TITLE ", "CURSOR ", "SAY ", "LEGEND ")


def fail(msg):
    print("WIRE2_CHECK_FAIL " + msg)
    sys.exit(1)


def raw_blocks(text):
    """(version, [lines]) for every complete block, in stream order."""
    out, cur, ver = [], None, 0
    for line in text.split("\n"):
        if line in ("SNAP v1 pad", "SNAP v2 pad"):
            if cur is not None:
                fail("truncated block before line %r" % line)
            cur, ver = [line], int(line[6])
            continue
        if cur is None:
            continue
        cur.append(line)
        if line == "END":
            out.append((ver, cur))
            cur = None
    return out


def v1_frame(lines):
    head = {}
    rows, dirty = [], None
    i = 1
    for k in HEAD:
        if not lines[i].startswith(k):
            fail("v1 header %r" % lines[i])
        head[k] = lines[i]
        i += 1
    if lines[i].startswith("DIRTY lines="):
        dirty = [int(x) for x in lines[i][12:].split(",") if x]
        i += 1
    n = int(lines[i].split("n=")[1])
    i += 1
    for r in range(n):
        t, h, m = lines[i], lines[i + 1], lines[i + 2]
        if not (t.startswith("T ") and h.startswith("H ") and m.startswith("M ")):
            fail("v1 row %d" % r)
        rows.append((t[2:], h[2:], m[2:]))
        i += 3
    return {"head": head, "rows": rows, "dirty": dirty, "full": dirty is None}


def v2_frame(lines, prev, prev_gen):
    g = lines[1].split()
    if g[0] != "GEN" or not g[2].startswith("base="):
        fail("v2 GEN %r" % lines[1])
    gen, base = int(g[1]), g[2][5:]
    head = {}
    i = 2
    for k in HEAD:
        if not lines[i].startswith(k):
            fail("v2 header %r" % lines[i])
        head[k] = lines[i]
        i += 1
    a = lines[i].split()
    if a[0] != "ROWS":
        fail("v2 ROWS %r" % lines[i])
    n, body = int(a[1][2:]), int(a[2][5:])
    i += 1
    sent = {}
    order = []
    while lines[i] != "END":
        if not lines[i].startswith("R "):
            fail("v2 expected R, got %r" % lines[i])
        r = int(lines[i][2:])
        if r in sent or r >= n:
            fail("v2 bad R %d (n=%d)" % (r, n))
        t, h, m = lines[i + 1], lines[i + 2], lines[i + 3]
        if not (t.startswith("T ") and h.startswith("H ") and m.startswith("M ")):
            fail("v2 row %d" % r)
        if not (len(t) == len(h) == len(m)):
            fail("v2 row %d lengths" % r)
        sent[r] = (t[2:], h[2:], m[2:])
        order.append(r)
        i += 4
    if base == "-":
        if len(sent) != n:
            fail("v2 full frame gen=%d sends %d of %d rows" % (gen, len(sent), n))
        rows = [sent[r] for r in range(n)]
    else:
        if prev is None or prev_gen is None or int(base) != prev_gen:
            fail("v2 gen=%d base=%s but last frame gen=%s" % (gen, base, prev_gen))
        rows = []
        for r in range(n):
            if r in sent:
                rows.append(sent[r])
            elif r < len(prev["rows"]):
                rows.append(prev["rows"][r])
            else:
                fail("v2 gen=%d leaves row %d unknown" % (gen, r))
    got = sum(3 * len(t) + 9 for t, _, _ in rows)
    if got != body:
        fail("v2 gen=%d body=%d rebuilt=%d" % (gen, body, got))
    return {"head": head, "rows": rows, "dirty": None if base == "-" else sorted(order),
            "full": base == "-", "gen": gen, "sent": len(order)}


def canon(f):
    return (tuple(f["head"][k] for k in HEAD), tuple(f["rows"]))


def as_v1(f):
    s = ["SNAP v1 pad"] + [f["head"][k] for k in HEAD]
    if f["dirty"] is not None:
        s.append("DIRTY lines=" + ",".join(map(str, f["dirty"])))
    s.append("ROWS n=%d" % len(f["rows"]))
    for t, h, m in f["rows"]:
        s += ["T " + t, "H " + h, "M " + m]
    return "\n".join(s + ["END", ""])


def segments(blob):
    parts = blob.split(b"\x1b]pad-frame\x07")
    return parts[:-1] if parts and parts[-1] == b"" else parts


def main():
    args = sys.argv[1:]
    opt = {"--view": None, "--out": None, "--min-frames": "2", "--min-v2": "1"}
    pos = []
    while args:
        a = args.pop(0)
        if a in opt:
            opt[a] = args.pop(0)
        else:
            pos.append(a)
    if len(pos) != 2:
        print(__doc__)
        sys.exit(2)
    t1, t2 = open(pos[0]).read(), open(pos[1]).read()
    b1, b2 = raw_blocks(t1), raw_blocks(t2)
    if any(v != 1 for v, _ in b1):
        fail("v1 stream holds v2 blocks")
    f1 = [v1_frame(ls) for _, ls in b1]
    f2, prev, gen = [], None, None
    for v, ls in b2:
        if v == 1:
            f = v1_frame(ls)
            gen = None
        else:
            f = v2_frame(ls, prev, gen)
            gen = f["gen"]
        f["bytes"] = sum(len(x) + 1 for x in ls)
        f["lines"] = len(ls)
        f["ver"] = v
        f2.append(f)
        prev = f
    for f, (_, ls) in zip(f1, b1):
        f["bytes"] = sum(len(x) + 1 for x in ls)
        f["lines"] = len(ls)
    keep, extra = [], []
    for i, f in enumerate(f2):
        if f["full"] and i > 0 and canon(f) == canon(f2[i - 1]):
            extra.append(i)
        else:
            keep.append(i)
    k2 = [f2[i] for i in keep]
    if len(k2) != len(f1):
        fail("frames v1=%d v2=%d (after %d requested full frames)" % (len(f1), len(k2), len(extra)))
    for j, (a, b) in enumerate(zip(f1, k2)):
        if canon(a) != canon(b):
            fail("frame %d differs (v2 block %d)" % (j, keep[j]))
    nv2 = sum(1 for f in f2 if f["ver"] == 2)
    if len(f1) < int(opt["--min-frames"]) or nv2 < int(opt["--min-v2"]):
        fail("too few frames v1=%d v2blocks=%d" % (len(f1), nv2))
    # sizes over the key frames both streams wrote as v2 vs v1
    pairs = [(a, b) for a, b in zip(f1, k2) if b["ver"] == 2]
    m = lambda xs: statistics.median(xs) if xs else 0
    v1b, v2b = m([a["bytes"] for a, _ in pairs]), m([b["bytes"] for _, b in pairs])
    v1l, v2l = m([a["lines"] for a, _ in pairs]), m([b["lines"] for _, b in pairs])
    rows = m([b["sent"] for _, b in pairs if not b["full"]])
    if opt["--out"]:
        os.makedirs(opt["--out"], exist_ok=True)
        with open(os.path.join(opt["--out"], "v2_rebuilt.txt"), "w") as fp:
            fp.write("".join(as_v1(f) for f in k2))
    if opt["--view"]:
        view = opt["--view"]
        out = opt["--out"] or "."

        def run(*a, stdin=None):
            return subprocess.run([view, *a], capture_output=True, check=False)
        st = run("--plain", "--stats", pos[1])
        if st.returncode != 0 or b" rejected=0 " not in st.stderr:
            fail("pad_view on v2: %s" % st.stderr.decode().strip())
        full1 = run("--replay-full", pos[0]).stdout
        full2 = run("--replay-full", pos[1]).stdout
        diff2 = run("--replay", pos[1]).stdout
        s1, s2 = segments(full1), segments(full2)
        if len(s1) != len(f1) or len(s2) != len(f2):
            fail("replay frames v1=%d/%d v2=%d/%d" % (len(s1), len(f1), len(s2), len(f2)))
        for j, i in enumerate(keep):
            if s1[j] != s2[i]:
                fail("C replay-full bytes differ at frame %d (v2 block %d)" % (j, i))
        open(os.path.join(out, "v2_diff.bin"), "wb").write(diff2)
        open(os.path.join(out, "v2_full.bin"), "wb").write(full2)
        tm = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "term_model.py"),
                             os.path.join(out, "v2_diff.bin"), os.path.join(out, "v2_full.bin")],
                            capture_output=True, text=True)
        print(tm.stdout.strip())
        if not tm.stdout.startswith("TERM_MODEL_OK"):
            fail("term_model on v2 replay")
    print("WIRE2_CHECK_OK frames=%d v2=%d requested_full=%d bytes_med v1=%g v2=%g lines_med v1=%g v2=%g rows_sent_med=%g"
          % (len(f1), nv2, len(extra), v1b, v2b, v1l, v2l, rows))


if __name__ == "__main__":
    main()
