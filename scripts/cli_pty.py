#!/usr/bin/env python3
"""End-to-end check of the installed one-command editor in a pty.

Usage: cli_pty.py SCENARIO FILE -- CMD ARGS...   (CMD is e.g. aura-pad FILE)

Starts CMD in a pseudo-terminal (80x24, TERM=xterm-256color), waits for
the first frame, types keys like a person (one write per key), and
checks what lands in FILE and on the terminal. Scenarios:

  open     FILE holds "(hello 1)\\nworld\\n": type "hi" at the start,
           ctrl-x ctrl-s, ctrl-q -> FILE is "hi(hello 1)\\nworld\\n"
  new      FILE is missing: type "abc", enter, "d", ctrl-x ctrl-s,
           ctrl-x ctrl-c -> FILE is "abc\\nd\\n"
  unsaved  FILE holds "pad\\n": type "x", ctrl-q -> still running, says
           "not saved yet", FILE unchanged; ctrl-q again -> exits,
           FILE still "pad\\n"
  emergency FILE holds "pad\\n": type "x", ctrl-\\ (SIGQUIT from the tty)
           -> exits 131 at once, FILE still "pad\\n"
  vi       FILE holds "ab\\ncd\\n": ctrl-f, ctrl-n, i, Z, Esc, q (must not
           insert), ctrl-x ctrl-s, ctrl-q -> FILE is "ab\\ncZd\\n" and the
           screen showed normal then insert then normal
  sentence FILE holds a define and an em dash. ctrl-e, one letter, Tab,
           save, Enter, quit, Enter. The letter is the only text change
           and the em dash bytes stay. Open again, Tab, Enter: SAY has
           "born line" and "used ". Then quit.

Typing in open / new / unsaved / emergency / vi presses i first. Those
scenarios run with PAD_CLASSIC=1, because the editor starts in vi normal
mode. sentence is the default binary: no PAD_CLASSIC.

The pty is the child's controlling terminal, so ctrl-c / ctrl-\\ act as
they would in a real terminal (aura-pad hands ctrl-c to Soft as a byte).

Every scenario also checks that the editor exits 0, that the terminal
is back in cooked mode (ICANON and ECHO on, as before the start) and
that the alternate screen was left. Prints CLI_PTY_OK scenario=.. or
CLI_PTY_FAIL with the reason and the tail of the screen bytes.
"""
import os, select, signal, struct, subprocess, sys, termios, time, fcntl

def fail(msg, out=b""):
    tail = out[-600:].decode("utf-8", "replace").replace("\x1b", "^[")
    print("CLI_PTY_FAIL " + msg + "\n--- screen tail ---\n" + tail)
    sys.exit(1)

def sentence_scenario(path, cmd):
    """Default surface: one letter, sentence save, sentence quit, then check."""
    raw = b"(define (mark x) x) ;; \xe2\x80\x94\n"
    want = b"(define (mark x) x) ;; \xe2\x80\x94z\n"
    name = os.path.basename(path)

    def drive(actions):
        m, s = os.openpty()
        fcntl.ioctl(s, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        before = termios.tcgetattr(s)
        env = dict(os.environ, TERM="xterm-256color")
        env.pop("NO_COLOR", None)
        env.pop("PAD_CLASSIC", None)
        def ctty():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        p = subprocess.Popen(cmd, stdin=s, stdout=s, stderr=s, env=env, preexec_fn=ctty)
        out = bytearray()

        def pump(t):
            end = time.time() + t
            while time.time() < end:
                r, _, _ = select.select([m], [], [], 0.05)
                if r:
                    try:
                        b = os.read(m, 65536)
                    except OSError:
                        return
                    if not b:
                        return
                    out.extend(b)
                elif p.poll() is not None:
                    return

        def wait_for(text, t=40.0):
            end = time.time() + t
            blob = text.encode() if isinstance(text, str) else text
            while time.time() < end:
                if blob in out:
                    return True
                if p.poll() is not None:
                    pump(0.3)
                    return blob in out
                pump(0.1)
            return blob in out

        def key(bs, settle=0.25):
            os.write(m, bytes(bs))
            pump(settle)

        actions(p, out, pump, wait_for, key)
        try:
            rc = p.wait(timeout=30)
        except subprocess.TimeoutExpired:
            p.kill()
            fail("editor did not exit after quit", out)
        pump(0.3)
        after = termios.tcgetattr(s)
        os.close(s)
        os.close(m)
        for flag, nm in ((termios.ICANON, "ICANON"), (termios.ECHO, "ECHO")):
            if (after[3] & flag) != (before[3] & flag):
                fail("terminal not restored (%s)" % nm, out)
        if b"\x1b[?1049h" not in out or out.rfind(b"\x1b[?1049l") < out.rfind(b"\x1b[?1049h"):
            fail("alternate screen not entered/left", out)
        return rc, out

    def letters(key, word):
        for ch in word:
            key([ord(ch)])

    open(path, "wb").write(raw)

    def edit(p, out, pump, wait_for, key):
        if not wait_for(name):
            fail("no first frame with the file name in the title", out)
        pump(0.4)
        key([5], 0.4)
        key([ord("z")])
        key([9], 0.4)
        letters(key, "save")
        key([13], 0.8)
        if not wait_for("saved ", 20):
            fail("no 'saved' say", out)
        letters(key, "quit")
        key([13], 0.2)

    rc, out = drive(edit)
    if rc != 0:
        fail("exit code %d" % rc, out)
    got = open(path, "rb").read()
    if got == want.replace(b"\xe2\x80\x94", b"-"):
        fail("em dash was written as a hyphen", out)
    if got != want:
        fail("file is %r, want %r" % (got, want), out)
    if got.count(b"\xe2\x80\x94") != 1:
        fail("em dash count is not 1", out)

    def check(p, out, pump, wait_for, key):
        if not wait_for(name):
            fail("reopen had no first frame", out)
        pump(0.4)
        key([9], 0.4)
        key([13], 0.5)
        if not wait_for("born line", 45):
            fail("empty Enter did not say the birth line", out)
        if b"used " not in out:
            fail("empty Enter did not say a use count", out)
        letters(key, "quit")
        key([13], 0.2)

    rc, out = drive(check)
    if rc != 0:
        fail("reopen exit code %d" % rc, out)
    if open(path, "rb").read() != want:
        fail("check rewrote the file", out)
    print("CLI_PTY_OK scenario=sentence bytes=%d file=%r" % (len(out), want))

def main():
    if len(sys.argv) < 5 or sys.argv[3] != "--":
        print(__doc__); sys.exit(2)
    scen, path, cmd = sys.argv[1], sys.argv[2], sys.argv[4:]
    if scen == "sentence":
        sentence_scenario(path, cmd)
        return
    name = os.path.basename(path)
    if scen == "open":
        open(path, "w").write("(hello 1)\nworld\n")
    elif scen == "new":
        if os.path.exists(path): os.unlink(path)
    elif scen in ("unsaved", "emergency"):
        open(path, "w").write("pad\n")
    elif scen == "vi":
        open(path, "w").write("ab\ncd\n")
    else:
        fail("unknown scenario " + scen)
    m, s = os.openpty()
    fcntl.ioctl(s, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    before = termios.tcgetattr(s)
    env = dict(os.environ, TERM="xterm-256color")
    env.pop("NO_COLOR", None)
    def ctty():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    p = subprocess.Popen(cmd, stdin=s, stdout=s, stderr=s, env=env, preexec_fn=ctty)
    out = bytearray()

    def pump(t):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([m], [], [], 0.05)
            if r:
                try:
                    b = os.read(m, 65536)
                except OSError:
                    return
                if not b:
                    return
                out.extend(b)
            elif p.poll() is not None:
                return

    def wait_for(text, t=40.0):
        end = time.time() + t
        while time.time() < end:
            if text.encode() in out:
                return True
            if p.poll() is not None:
                pump(0.3)
                return text.encode() in out
            pump(0.1)
        return text.encode() in out

    def key(bs, settle=0.25):
        os.write(m, bytes(bs))
        pump(settle)

    def typed(s):
        for ch in s:
            key([ord(ch)])

    def mode_is(want, t=10.0):
        # The screen log keeps old frames, so the latest badge wins.
        end = time.time() + t
        while time.time() < end:
            n = out.rfind(b"[normal]")
            i = out.rfind(b"[insert]")
            got = "normal" if n > i else ("insert" if i >= 0 else "")
            if got == want:
                return True
            if p.poll() is not None:
                pump(0.3)
                n = out.rfind(b"[normal]")
                i = out.rfind(b"[insert]")
                got = "normal" if n > i else ("insert" if i >= 0 else "")
                return got == want
            pump(0.1)
        return False

    def enter_insert():
        key([105], 0.4)  # i — aura-pad starts in vi normal mode
        if not mode_is("insert"):
            fail("did not enter insert mode", out)

    if not wait_for("== aura pad: " + name):
        fail("no first frame with the file name in the title", out)
    pump(0.5)
    if scen == "open":
        if not wait_for("opened " + name):
            fail("no 'opened' say", out)
        if not mode_is("normal"):
            fail("did not start in normal mode", out)
        enter_insert()
        typed("hi")
        key([24]); key([19])
        if not wait_for("saved " + name, 10):
            fail("no 'saved' say", out)
        key([17], 0.1)
        want = "hi(hello 1)\nworld\n"
    elif scen == "new":
        if not wait_for("new page " + name):
            fail("no 'new page' say", out)
        enter_insert()
        typed("abc"); key([13]); typed("d")
        key([24]); key([19])
        if not wait_for("saved " + name, 10):
            fail("no 'saved' say", out)
        key([24]); key([3], 0.1)
        want = "abc\nd\n"
    elif scen == "emergency":
        enter_insert()
        typed("x")
        key([28], 0.1)
        want = "pad\n"
    elif scen == "vi":
        if not mode_is("normal"):
            fail("did not start in normal mode", out)
        key([6]); key([14])          # ctrl-f, ctrl-n
        enter_insert()
        key([90])                    # Z
        key([27], 0.4)               # Esc
        if not mode_is("normal"):
            fail("Esc did not return to normal mode", out)
        key([113])                   # q must not insert in normal mode
        key([24]); key([19])
        if not wait_for("saved " + name, 10):
            fail("no 'saved' say", out)
        key([17], 0.1)
        want = "ab\ncZd\n"
    else:
        enter_insert()
        typed("x")
        key([17])
        if not wait_for("not saved yet", 10):
            fail("no 'not saved yet' say", out)
        if p.poll() is not None:
            fail("quit with unsaved changes on the first ctrl-q", out)
        if open(path).read() != "pad\n":
            fail("file changed before any save", out)
        key([17], 0.1)
        want = "pad\n"
    try:
        rc = p.wait(timeout=20)
    except subprocess.TimeoutExpired:
        p.kill()
        fail("editor did not exit after quit", out)
    pump(0.3)
    after = termios.tcgetattr(s)
    os.close(s)
    os.close(m)
    if rc != (131 if scen == "emergency" else 0):
        fail("exit code %d" % rc, out)
    got = open(path).read() if os.path.exists(path) else None
    if got != want:
        fail("file is %r, want %r" % (got, want), out)
    for flag, nm in ((termios.ICANON, "ICANON"), (termios.ECHO, "ECHO")):
        if (after[3] & flag) != (before[3] & flag):
            fail("terminal not restored (%s)" % nm, out)
    # the last alternate-screen switch must be "leave" (a docker client
    # may still print a line after aura-pad has left it)
    if b"\x1b[?1049h" not in out or out.rfind(b"\x1b[?1049l") < out.rfind(b"\x1b[?1049h"):
        fail("alternate screen not entered/left", out)
    print("CLI_PTY_OK scenario=%s bytes=%d file=%r" % (scen, len(out), got))

if __name__ == "__main__":
    main()
