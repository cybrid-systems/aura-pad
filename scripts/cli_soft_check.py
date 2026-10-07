#!/usr/bin/env python3
"""Soft file mode (soft/pad/file.aura) checked headless, case by case.

Usage: cli_soft_check.py OUTDIR

Each case writes a file under OUTDIR, runs soft/pad/play.aura through
scripts/run_soft.sh with PAD_FILE set and a fixed protocol stream (the
"IN ..." lines pad_play / aura-pad would send), then checks the file
bytes and the TITLE / SAY / rows of the frames Soft wrote. OUTDIR must
be inside the repo (run_soft.sh mounts the repo at /workspace/aura-pad).
Prints CLI_SOFT_OK cases=N or CLI_SOFT_FAIL case=.. why.
"""
import os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOX = "/workspace/aura-pad"
OUT = os.path.abspath(sys.argv[1])
os.makedirs(OUT, exist_ok=True)

def frames(text):
    fs, cur = [], None
    for ln in text.split("\n"):
        if ln in ("SNAP v1 pad", "SNAP v2 pad"):
            cur = {"rows": []}
        elif cur is None:
            continue
        elif ln.startswith("TITLE "):
            cur["title"] = ln[6:]
        elif ln.startswith("SAY "):
            cur["say"] = ln[4:]
        elif ln.startswith("T "):
            cur["rows"].append(ln[2:])
        elif ln == "END":
            fs.append(cur)
            cur = None
    return fs

def run(name, content, lines, path=None):
    p = path or os.path.join(OUT, name + ".txt")
    if content is None:
        if os.path.exists(p):
            os.unlink(p)
    else:
        open(p, "wb").write(content)
    env = dict(os.environ, PAD_FILE=BOX + p[len(ROOT):], PAD_PAGE="", PAD_DEFER="")
    r = subprocess.run(["bash", os.path.join(ROOT, "scripts/run_soft.sh"), BOX + "/soft/pad/play.aura"],
                       input="".join(l + "\n" for l in lines), capture_output=True, text=True, env=env)
    open(os.path.join(OUT, name + ".out"), "w").write(r.stdout)
    open(os.path.join(OUT, name + ".err"), "w").write(r.stderr)
    bad = [l for l in (r.stdout + r.stderr).split("\n") if "error:" in l.lower() or "unbound variable" in l]
    if bad:
        fail(name, "Soft error: " + bad[0])
    data = open(p, "rb").read() if os.path.exists(p) else None
    return frames(r.stdout), data

def fail(name, why):
    print("CLI_SOFT_FAIL case=%s %s" % (name, why))
    sys.exit(1)

def need(name, cond, why):
    if not cond:
        fail(name, why)

n = 0
def case(fn):
    global n
    fn()
    n += 1

def c_open_save():
    f, d = run("open_save", b"(hello 1)\nworld\n", ["IN 108", "IN 24", "IN 19", "IN 17"])
    need("open_save", f[0]["title"].startswith("aura pad: open_save.txt keys="), "title %r" % f[0]["title"])
    need("open_save", f[0]["say"].startswith("opened open_save.txt (2 lines)"), "say %r" % f[0]["say"])
    need("open_save", f[0]["rows"] == ["(hello 1)", "world"], "rows %r" % f[0]["rows"])
    need("open_save", f[-1]["say"] == "saved open_save.txt (2 lines)", "say %r" % f[-1]["say"])
    need("open_save", d == b"l(hello 1)\nworld\n", "file %r" % d)

def c_fast_cx():
    f, d = run("fast_cx", b"a\n", ["IN 98", "IN 24 19", "QUIT"])
    need("fast_cx", d == b"ba\n", "file %r" % d)
    need("fast_cx", f[-1]["say"] == "saved fast_cx.txt (1 line)", "say %r" % f[-1]["say"])

def c_nonl():
    f, d = run("nonl", b"abc", ["IN 120", "IN 24", "IN 19", "QUIT"])
    need("nonl", d == b"xabc", "file %r (no newline at the end must stay so)" % d)

def c_unmod():
    for nm, body in (("unmod", b"a\n\nb\n"), ("unmod_nl", b"\n"), ("unmod_empty", b"")):
        f, d = run(nm, body, ["IN 24", "IN 19", "QUIT"])
        need(nm, d == body, "unchanged save rewrote %r as %r" % (body, d))

def c_new():
    f, d = run("new", None, ["IN 104", "IN 105", "IN 24", "IN 19", "QUIT"])
    need("new", f[0]["say"].startswith("new page new.txt"), "say %r" % f[0]["say"])
    need("new", f[0]["rows"] == [""], "rows %r" % f[0]["rows"])
    need("new", d == b"hi\n", "file %r" % d)
    f, d = run("new_empty", None, ["IN 24", "IN 19", "QUIT"])
    need("new_empty", d == b"", "file %r" % d)
    f, d = run("new_quit", None, ["IN 17"])
    need("new_quit", d is None, "quit without save created the file")

def c_unsaved():
    f, d = run("unsaved", b"pad\n", ["IN 120", "IN 17", "IN 104", "IN 17", "IN 17", "IN 98"])
    says = [x["say"] for x in f]
    need("unsaved", len(f) == 5 and "not saved yet" in says[2] and says[3] == "ctrl-x ctrl-s saves, ctrl-q quits"
         and "not saved yet" in says[4], "says %r" % says)
    need("unsaved", f[-1]["rows"] == ["xhpad"], "the key after a refused quit was lost or quit early: %r" % f[-1]["rows"])
    need("unsaved", d == b"pad\n", "file %r" % d)
    # ctrl-x ctrl-c: refused once, the armed quit survives the next ctrl-x
    f, d = run("unsaved_cx", b"pad\n", ["IN 120", "IN 24", "IN 3", "IN 24", "IN 3", "IN 98"])
    says = [x["say"] for x in f]
    need("unsaved_cx", sum("not saved yet" in s for s in says) == 1, "says %r" % says)
    need("unsaved_cx", f[-1]["rows"] == ["xpad"], "did not quit on the second ctrl-x ctrl-c: %r" % f[-1]["rows"])

def c_ro():
    long = b"x" * 80 + b"\n"
    f, d = run("ro_long", long, ["IN 5", "IN 127", "IN 24", "IN 19", "IN 17", "IN 98"])
    need("ro_long", f[0]["title"].startswith("aura pad: ro_long.txt (look only) keys="), "title %r" % f[0]["title"])
    need("ro_long", f[0]["rows"] == ["x" * 72], "rows %r" % f[0]["rows"])
    need("ro_long", any("stays as it was" in x["say"] for x in f), "says %r" % [x["say"] for x in f])
    need("ro_long", len(f) == 5 and f[-1]["rows"] == ["x" * 71],
         "edited look-only page: quit refused or keys lost: %d frames, %r" % (len(f), f[-1]["rows"]))
    need("ro_long", d == long, "look-only file was written")
    f, d = run("ro_tab", b"a\tb\n", ["IN 17"])
    need("ro_tab", f[0]["rows"] == ["a?b"] and "(look only)" in f[0]["title"], "frame %r" % f[0])
    need("ro_tab", d == b"a\tb\n", "file %r" % d)
    many = b"".join(b"line %d\n" % i for i in range(25))
    f, d = run("ro_lines", many, ["IN 17"])
    need("ro_lines", len(f[0]["rows"]) == 18 and "(look only)" in f[0]["title"], "rows %d" % len(f[0]["rows"]))
    utf = "héllo\n".encode()
    f, d = run("ro_utf8", utf, ["IN 17"])
    need("ro_utf8", "(look only)" in f[0]["title"] and f[0]["rows"] == ["h??llo"], "frame %r" % f[0])
    fit = b"".join(b"y" * 72 + b"\n" for _ in range(18))
    f, d = run("fits", fit, ["IN 24", "IN 19", "QUIT"])
    need("fits", "(look only)" not in f[0]["title"] and d == fit, "18 x 72 must open editable and save as is")

def c_fail():
    p = os.path.join(OUT, "nodir", "x.txt")
    f, d = run("save_fail", None, ["IN 97", "IN 24", "IN 19", "QUIT"], path=p)
    need("save_fail", f[-1]["say"].startswith("could not save x.txt"), "say %r" % f[-1]["say"])

def c_hints():
    f, d = run("hints", b"q\n", ["IN 19", "IN 3", "IN 24", "IN 97", "QUIT"])
    says = [x["say"] for x in f]
    need("hints", says[1] == "to save hints.txt, press ctrl-x then ctrl-s", "says %r" % says)
    need("hints", says[2] == "to quit press ctrl-q (ctrl-x ctrl-c works too)", "says %r" % says)
    need("hints", says[4] == "ctrl-x and that key do not go together" and f[-1]["rows"] == ["q"],
         "ctrl-x a: %r %r" % (says, f[-1]["rows"]))
    need("hints", d == b"q\n", "file %r" % d)

for fn in (c_open_save, c_fast_cx, c_nonl, c_unmod, c_new, c_unsaved, c_ro, c_fail, c_hints):
    case(fn)
print("CLI_SOFT_OK cases=%d" % n)
