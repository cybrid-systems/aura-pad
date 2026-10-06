#!/usr/bin/env python3
"""Keystroke -> terminal-output latency for terminal editors, one pty.

Same method for every editor: start it in a pseudo-terminal (80x24,
TERM=xterm-256color) on the same file, run its setup keys, then for each
measured key write the key bytes and time

  first  = first output byte after the write
  done   = last output byte before the output stays quiet for --quiet ms

over --n repetitions (each key is followed by its undo key, also
measured). Reports median / p90 in microseconds per key and the median
number of bytes the editor wrote to the terminal per key. This measures
what the editor writes to the terminal, not photons: the terminal
emulator's own rendering is excluded for every editor alike.

Usage: latency_pty.py --name NAME --setup-keys HEX[,HEX...] -- CMD ARGS...
Keys are given as hex byte strings (e.g. 61 = 'a', 1b5b44 = left).
"""
import argparse, os, pty, select, signal, statistics, struct, sys, time, fcntl, termios

def drain(fd, quiet_s, max_s):
    """read until no output for quiet_s; return (first_t, last_t, nbytes)."""
    t_end = time.perf_counter() + max_s
    first = last = None
    n = 0
    while True:
        now = time.perf_counter()
        if now >= t_end:
            break
        wait = quiet_s if last is not None else min(max_s, t_end - now)
        r, _, _ = select.select([fd], [], [], wait)
        if not r:
            if last is not None:
                break
            continue
        try:
            b = os.read(fd, 65536)
        except OSError:
            break
        if not b:
            break
        t = time.perf_counter()
        if first is None:
            first = t
        last = t
        n += len(b)
    return first, last, n

def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p * (len(xs) - 1))))]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--setup-keys", default="")
    ap.add_argument("--pairs", default="61:7f,1b5b44:1b5b43",
                    help="key:undo pairs, hex, comma separated")
    ap.add_argument("--labels", default="insert,cursor")
    ap.add_argument("--n", type=int, default=60)
    ap.add_argument("--quiet", type=float, default=60.0, help="ms")
    ap.add_argument("--startup-quiet", type=float, default=1500.0, help="ms")
    ap.add_argument("--cold", default="", help="hex key:undo measured once per --cold-n "
                    "with a long quiet window (deferred redisplay shows up)")
    ap.add_argument("--cold-n", type=int, default=5)
    ap.add_argument("--cold-quiet", type=float, default=1200.0, help="ms")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.environ.pop("NO_COLOR", None)
        os.execvp(cmd[0], cmd)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    t0 = time.perf_counter()
    f, l, n = drain(fd, a.startup_quiet / 1000.0, 60.0)
    startup = (l - t0) if l else -1
    for hx in [k for k in a.setup_keys.split(",") if k]:
        os.write(fd, bytes.fromhex(hx))
        drain(fd, 0.25, 5.0)
    out = {"name": a.name, "startup_ms": round(startup * 1000)}
    labels = a.labels.split(",")
    for lab, pair in zip(labels, a.pairs.split(",")):
        k, u = pair.split(":")
        res = {"first": [], "done": [], "ufirst": [], "udone": [], "bytes": []}
        for _ in range(a.n):
            for key, fk, dk in ((k, "first", "done"), (u, "ufirst", "udone")):
                ts = time.perf_counter()
                os.write(fd, bytes.fromhex(key))
                f, l, nb = drain(fd, a.quiet / 1000.0, 5.0)
                if f is None:
                    continue
                res[fk].append((f - ts) * 1e6)
                res[dk].append((l - ts) * 1e6)
                res["bytes"].append(nb)
        both = res["done"] + res["udone"]
        bothf = res["first"] + res["ufirst"]
        out[lab] = {"n": len(both),
                    "first_med_us": round(statistics.median(bothf)) if bothf else -1,
                    "done_med_us": round(statistics.median(both)) if both else -1,
                    "done_p90_us": round(pct(both, 0.9)) if both else -1,
                    "bytes_med": round(statistics.median(res["bytes"])) if res["bytes"] else -1}
    if a.cold:
        k, u = a.cold.split(":")
        opens, closes, opens_q, closes_q, opens_f, closes_f = [], [], [], [], [], []
        for _ in range(a.cold_n):
            for key, dst, dstq, dstf in ((k, opens, opens_q, opens_f), (u, closes, closes_q, closes_f)):
                ts = time.perf_counter()
                os.write(fd, bytes.fromhex(key))
                # immediate frame (short quiet), then anything deferred
                f, l, nb = drain(fd, a.quiet / 1000.0, 5.0)
                f2, l2, nb2 = drain(fd, a.cold_quiet / 1000.0, 5.0)
                if l is not None:
                    dst.append((l - ts) * 1e6)
                    dstf.append((f - ts) * 1e6)
                    dstq.append(((l2 if l2 else l) - ts) * 1e6)
        out["string_open"] = {"n": len(opens), "first_med_us": round(statistics.median(opens_f)) if opens_f else -1,
                              "done_med_us": round(statistics.median(opens)) if opens else -1,
                              "all_output_med_us": round(statistics.median(opens_q)) if opens_q else -1}
        out["string_close"] = {"n": len(closes), "first_med_us": round(statistics.median(closes_f)) if closes_f else -1,
                               "done_med_us": round(statistics.median(closes)) if closes else -1,
                               "all_output_med_us": round(statistics.median(closes_q)) if closes_q else -1}
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
    print("LATENCY " + " ".join(
        f"{key}={val}" if not isinstance(val, dict) else
        f"{key}:" + ",".join(f"{k2}={v2}" for k2, v2 in val.items())
        for key, val in out.items()))
    sys.stdout.flush()

if __name__ == "__main__":
    main()
