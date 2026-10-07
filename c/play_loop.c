/* play_loop: the interactive thin viewport loop shared by pad_play and
 * aura-pad. Forwards the raw key bytes of each read() as one
 * "IN <b1> <b2> ..." line without interpreting them, and blits each SNAP
 * block Soft sends back. Soft owns the keymap, the gate, the buffer, the
 * cursor, the file and the kid words; a key quits because Soft decides it
 * means quit. stdin EOF closes the child's stdin; child EOF ends the
 * viewport. Ctrl-C still works (ISIG stays on) and restores the terminal;
 * with editor_tty (aura-pad) ctrl-c and ctrl-z are plain key bytes for
 * Soft like every other key, and ctrl-\ (SIGQUIT) is the emergency exit.
 * wire 2 offers Soft wire v2 ("WIRE 2" line; Soft decides to use it and
 * then sends only the rows it marked DIRTY). When the reader drops a v2
 * block (wrong base, unknown row, bad body length) C asks once for a full
 * frame ("WIRE 2 FULL") and draws nothing it cannot rebuild exactly. */
#define _POSIX_C_SOURCE 200809L

#include "play_loop.h"
#include "snap.h"

#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static struct termios g_saved;
static volatile sig_atomic_t g_raw = 0;
static volatile sig_atomic_t g_alt = 0;

static const char ALT_ON[] = "\033[?1049h";
static const char ALT_OFF[] = "\033[?1049l";

static void term_restore(void) {
    if (g_raw) {
        tcsetattr(STDIN_FILENO, TCSANOW, &g_saved);
        g_raw = 0;
    }
    if (g_alt) {
        fflush(stdout);
        if (write(STDOUT_FILENO, ALT_OFF, sizeof(ALT_OFF) - 1) < 0) { /* best effort */ }
        g_alt = 0;
    }
}

/* async-signal-safe: tcsetattr and write only */
static void on_signal(int sig) {
    if (g_raw)
        tcsetattr(STDIN_FILENO, TCSANOW, &g_saved);
    if (g_alt && write(STDOUT_FILENO, ALT_OFF, sizeof(ALT_OFF) - 1) < 0) { /* best effort */ }
    _exit(128 + sig);
}

static void term_raw(int editor_tty) {
    struct termios t;
    if (!isatty(STDIN_FILENO) || tcgetattr(STDIN_FILENO, &g_saved) != 0)
        return;
    t = g_saved;
    t.c_lflag &= (tcflag_t) ~(ICANON | ECHO | IEXTEN);
    t.c_iflag &= (tcflag_t) ~(IXON | ICRNL);
    if (editor_tty) { /* the bytes go to Soft; VQUIT keeps a way out */
        t.c_cc[VINTR] = _POSIX_VDISABLE;
        t.c_cc[VSUSP] = _POSIX_VDISABLE;
    }
    t.c_cc[VMIN] = 1;
    t.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSANOW, &t) == 0)
        g_raw = 1;
}

int pad_play_loop(pid_t pid, int to, int from, const PadPlayOpt *o) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGQUIT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);
    /* One write() per frame: a tty stdout is line-buffered by default,
     * which made every frame ~45 writes; the blit fflush()es at its end. */
    static char obuf[1 << 16];
    setvbuf(stdout, obuf, _IOFBF, sizeof(obuf));

    PadReader rd;
    if (!pad_reader_init(&rd)) {
        fprintf(stderr, "%s: out of memory\n", o->name);
        return 1;
    }
    if (o->altscreen && o->mode && !o->final_only && isatty(STDOUT_FILENO)) {
        fputs(ALT_ON, stdout);
        fflush(stdout);
        g_alt = 1;
    }
    term_raw(o->editor_tty);
    atexit(term_restore);
    if (o->wire == 2 && write(to, "WIRE 2\n", 7) != 7) {
        close(to);
        to = -1;
    }

    char line[PAD_MAX_COLS + 64];
    size_t ln = 0;
    int overflow = 0, keys = 0, asks = 0;
    PadSnap prev;
    memset(&prev, 0, sizeof(prev));
    prev.dirty_n = -1;
    int have_prev = 0;
    for (;;) {
        struct pollfd fds[2] = {{from, POLLIN, 0}, {to >= 0 ? STDIN_FILENO : -1, POLLIN, 0}};
        if (poll(fds, 2, -1) < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (fds[1].revents & (POLLIN | POLLHUP)) {
            unsigned char kb[64];
            ssize_t k = read(STDIN_FILENO, kb, sizeof(kb));
            if (k <= 0) {
                close(to); /* Soft sees EOF and finishes */
                to = -1;
            } else {
                /* One line per read(): "IN b1 b2 ... bn". An arrow key
                 * arrives as one read, so Soft gets one line per key
                 * (one pipe write, one Soft entry) instead of three.
                 * The bytes stay uninterpreted; Soft splits them. */
                char msg[8 + sizeof(kb) * 4];
                int m = 2;
                memcpy(msg, "IN", 2);
                for (ssize_t i = 0; i < k; i++)
                    m += snprintf(msg + m, sizeof(msg) - (size_t)m, " %u", kb[i]);
                msg[m++] = '\n';
                if (write(to, msg, (size_t)m) != m) { close(to); to = -1; }
                keys += (int)k;
            }
        }
        if (fds[0].revents & (POLLIN | POLLHUP)) {
            char buf[4096];
            ssize_t k = read(from, buf, sizeof(buf));
            if (k <= 0)
                break; /* Soft is done */
            for (ssize_t i = 0; i < k; i++) {
                if (buf[i] != '\n') {
                    if (ln + 1 < sizeof(line)) line[ln++] = buf[i];
                    else overflow = 1;
                    continue;
                }
                line[ln] = '\0';
                if (ln > 0 && line[ln - 1] == '\r') line[ln - 1] = '\0';
                /* an over-long line poisons its block: feed a non-wire line */
                if (pad_reader_line(&rd, overflow ? "#overflow" : line) && !o->final_only) {
                    pad_blit_dirty(stdout, have_prev ? &prev : NULL, &rd.last, o->mode);
                    pad_snap_free(&prev);
                    /* rd.last owns its row strings and the reader frees
                     * them on the next block; keep our own copies of the
                     * rows for the next diff. */
                    prev = rd.last;
                    for (int r = 0; r < prev.nrows; r++) {
                        prev.t[r] = prev.t[r] ? strdup(prev.t[r]) : NULL;
                        prev.h[r] = prev.h[r] ? strdup(prev.h[r]) : NULL;
                        prev.m[r] = prev.m[r] ? strdup(prev.m[r]) : NULL;
                    }
                    have_prev = 1;
                }
                if (rd.need_full && to >= 0) { /* rebuild failed: ask, never guess */
                    rd.need_full = 0;
                    rd.asked = 1;
                    asks++;
                    if (write(to, "WIRE 2 FULL\n", 12) != 12) { close(to); to = -1; }
                }
                ln = 0;
                overflow = 0;
            }
        }
    }
    if (to >= 0) close(to);
    close(from);
    int status = 0;
    waitpid(pid, &status, 0);
    term_restore();
    pad_reader_finish(&rd);
    pad_snap_free(&prev);
    int ok = rd.accepted > 0;
    if (ok && o->final_only)
        pad_blit(stdout, &rd.last, o->mode);
    fflush(stdout);
    if (o->stats && ok)
        fprintf(stderr, "PAD_C_PLAY keys=%d snaps=%d rejected=%d cursor=%d:%d wire=%d v2=%d v2_rows=%d asks=%d\n",
                keys, rd.accepted, rd.rejected, rd.last.cur_line, rd.last.cur_col, o->wire,
                rd.v2, rd.v2_rows, asks);
    if (!ok)
        fprintf(stderr, "%s: Soft sent no accepted snapshot\n", o->name);
    pad_reader_free(&rd);
    return ok ? 0 : 1;
}
