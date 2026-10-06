/* pad_play: interactive thin viewport. Spawns the Soft play child
 * (scripts/soft_play.sh -> soft/pad/play.aura), forwards the raw key
 * bytes of each read() as one "IN <b1> <b2> ..." line without
 * interpreting them, and blits each SNAP block
 * Soft sends back. Soft owns the keymap, the gate, the buffer, the cursor
 * and the kid words; ctrl-q quits because Soft decides it means quit.
 * stdin EOF closes the child's stdin; child EOF ends the viewport.
 * Ctrl-C still works (ISIG stays on). */
#define _POSIX_C_SOURCE 200809L

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
static int g_raw = 0;

static void term_restore(void) {
    if (g_raw) {
        tcsetattr(STDIN_FILENO, TCSANOW, &g_saved);
        g_raw = 0;
    }
}

static void term_raw(void) {
    struct termios t;
    if (!isatty(STDIN_FILENO) || tcgetattr(STDIN_FILENO, &g_saved) != 0)
        return;
    t = g_saved;
    t.c_lflag &= (tcflag_t) ~(ICANON | ECHO | IEXTEN);
    t.c_iflag &= (tcflag_t) ~(IXON | ICRNL);
    t.c_cc[VMIN] = 1;
    t.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSANOW, &t) == 0) {
        g_raw = 1;
        atexit(term_restore);
    }
}

static pid_t spawn(const char *script, int *to_fd, int *from_fd) {
    int in[2], out[2];
    if (pipe(in) != 0 || pipe(out) != 0)
        return -1;
    pid_t pid = fork();
    if (pid < 0)
        return -1;
    if (pid == 0) {
        dup2(in[0], STDIN_FILENO);
        dup2(out[1], STDOUT_FILENO);
        close(in[0]); close(in[1]); close(out[0]); close(out[1]);
        execlp("bash", "bash", script, (char *)NULL);
        _exit(127);
    }
    close(in[0]);
    close(out[1]);
    *to_fd = in[1];
    *from_fd = out[0];
    return pid;
}

static void usage(const char *a0) {
    fprintf(stderr,
            "usage: %s [--ansi|--plain] [--final] [--stats] [soft_play.sh]\n"
            "  forwards key bytes to Soft, blits Soft SNAP blocks.\n"
            "  --final draws only the last frame (headless/CI).\n",
            a0);
}

int main(int argc, char **argv) {
    const char *script = "scripts/soft_play.sh";
    int mode = -1, final_only = 0, stats = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--ansi") == 0) mode = 1;
        else if (strcmp(argv[i], "--plain") == 0) mode = 0;
        else if (strcmp(argv[i], "--final") == 0) final_only = 1;
        else if (strcmp(argv[i], "--stats") == 0) stats = 1;
        else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else if (argv[i][0] == '-') {
            usage(argv[0]);
            return 2;
        } else script = argv[i];
    }
    if (mode < 0)
        mode = isatty(STDOUT_FILENO) && getenv("NO_COLOR") == NULL;
    signal(SIGPIPE, SIG_IGN);
    /* One write() per frame: a tty stdout is line-buffered by default,
     * which made every frame ~45 writes; the blit fflush()es at its end. */
    static char obuf[1 << 16];
    setvbuf(stdout, obuf, _IOFBF, sizeof(obuf));

    int to = -1, from = -1;
    pid_t pid = spawn(script, &to, &from);
    if (pid < 0) {
        fprintf(stderr, "pad_play: cannot start %s\n", script);
        return 1;
    }
    PadReader rd;
    if (!pad_reader_init(&rd)) {
        fprintf(stderr, "pad_play: out of memory\n");
        return 1;
    }
    term_raw();

    char line[PAD_MAX_COLS + 64];
    size_t ln = 0;
    int overflow = 0, keys = 0;
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
                if (pad_reader_line(&rd, overflow ? "#overflow" : line) && !final_only) {
                    pad_blit_dirty(stdout, have_prev ? &prev : NULL, &rd.last, mode);
                    pad_snap_free(&prev);
                    /* shallow-keep row pointers would dangle; re-blit path
                     * only needs metadata + row strings Soft already owns
                     * in rd.last, so copy by re-parsing is heavy — instead
                     * snapshot fields we compare (title/say/cursor/nrows)
                     * and strdup rows Soft sent. */
                    prev = rd.last;
                    for (int r = 0; r < prev.nrows; r++) {
                        prev.t[r] = prev.t[r] ? strdup(prev.t[r]) : NULL;
                        prev.h[r] = prev.h[r] ? strdup(prev.h[r]) : NULL;
                        prev.m[r] = prev.m[r] ? strdup(prev.m[r]) : NULL;
                    }
                    have_prev = 1;
                    /* rd.last still owns its own copies; we duplicated. */
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
    if (ok && final_only)
        pad_blit(stdout, &rd.last, mode);
    if (stats && ok)
        fprintf(stderr, "PAD_C_PLAY keys=%d snaps=%d rejected=%d cursor=%d:%d\n",
                keys, rd.accepted, rd.rejected, rd.last.cur_line, rd.last.cur_col);
    if (!ok)
        fprintf(stderr, "pad_play: Soft sent no accepted snapshot\n");
    pad_reader_free(&rd);
    return ok ? 0 : 1;
}
