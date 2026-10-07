/* pad_play: interactive thin viewport for development and the smokes.
 * Spawns the Soft play child script (scripts/soft_play.sh ->
 * soft/pad/play.aura) and runs the shared loop (play_loop.c): raw key
 * bytes go to Soft as "IN <b1> <b2> ..." lines, SNAP blocks come back
 * and are blitted. Soft owns the keymap, the gate, the buffer, the cursor
 * and the kid words. The installed one-command editor is aura-pad
 * (aura_pad.c), which starts Soft itself without any script. */
#define _POSIX_C_SOURCE 200809L

#include "play_loop.h"
#include "errlog.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

static void close2(int p[2]) {
    if (p[0] >= 0) close(p[0]);
    if (p[1] >= 0) close(p[1]);
}

static pid_t spawn(const char *script, int *to_fd, int *from_fd, int *err_fd) {
    int in[2] = {-1, -1}, out[2] = {-1, -1}, err[2] = {-1, -1};
    if (pipe(in) != 0 || pipe(out) != 0 || pipe(err) != 0) {
        close2(in); close2(out); close2(err);
        return -1;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close2(in); close2(out); close2(err);
        return -1;
    }
    if (pid == 0) {
        dup2(in[0], STDIN_FILENO);
        dup2(out[1], STDOUT_FILENO);
        dup2(err[1], STDERR_FILENO);
        close2(in); close2(out); close2(err);
        execlp("bash", "bash", script, (char *)NULL);
        _exit(127);
    }
    close(in[0]);
    close(out[1]);
    close(err[1]);
    *to_fd = in[1];
    *from_fd = out[0];
    *err_fd = err[0];
    return pid;
}

static void usage(const char *a0) {
    fprintf(stderr,
            "usage: %s [--ansi|--plain] [--final] [--stats] [--wire1|--wire2] [soft_play.sh]\n"
            "  forwards key bytes to Soft, blits Soft SNAP blocks.\n"
            "  --final draws only the last frame (headless/CI).\n"
            "  --wire2 offers SNAP v2 (changed rows only); --wire1 keeps v1.\n",
            a0);
}

int main(int argc, char **argv) {
    const char *script = "scripts/soft_play.sh";
    PadPlayOpt o = {"pad_play", -1, 0, 0, 1, 0, 0};
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--ansi") == 0) o.mode = 1;
        else if (strcmp(argv[i], "--plain") == 0) o.mode = 0;
        else if (strcmp(argv[i], "--final") == 0) o.final_only = 1;
        else if (strcmp(argv[i], "--stats") == 0) o.stats = 1;
        else if (strcmp(argv[i], "--wire2") == 0) o.wire = 2;
        else if (strcmp(argv[i], "--wire1") == 0) o.wire = 1;
        else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else if (argv[i][0] == '-') {
            usage(argv[0]);
            return 2;
        } else script = argv[i];
    }
    if (o.mode < 0)
        o.mode = isatty(STDOUT_FILENO) && getenv("NO_COLOR") == NULL;
    int to = -1, from = -1, errfd = -1;
    pid_t pid = spawn(script, &to, &from, &errfd);
    if (pid < 0) {
        fprintf(stderr, "pad_play: cannot start %s\n", script);
        pad_errlog_msg("pad_play", "cannot start Soft");
        return 1;
    }
    return pad_play_loop(pid, to, from, errfd, &o);
}
