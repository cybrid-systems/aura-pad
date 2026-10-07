/* Shared interactive loop of the thin viewport (pad_play, aura-pad).
 * C forwards raw key bytes to the Soft child and blits the SNAP blocks it
 * sends back. It never learns what a key means. */
#ifndef PAD_PLAY_LOOP_H
#define PAD_PLAY_LOOP_H

#include <sys/types.h>

typedef struct {
    const char *name; /* prefix for messages: "pad_play" / "aura-pad" */
    int mode;         /* 1 ANSI, 0 plain */
    int final_only;   /* draw only the last frame (headless) */
    int stats;        /* PAD_C_PLAY line on stderr */
    int wire;         /* 1 or 2 (offer "WIRE 2") */
    int altscreen;    /* use the terminal's alternate screen (ANSI tty) */
    int editor_tty;   /* ctrl-c / ctrl-z reach Soft as bytes (no SIGINT /
                         SIGTSTP); ctrl-\ stays the emergency exit */
} PadPlayOpt;

/* Runs until the Soft child closes its stdout. to/from are the child's
 * stdin (write end) and stdout (read end); errfd is the child's stderr
 * (-1 if it was not captured). All three are closed here, and the child
 * is reaped. Returns the process exit code (0 if Soft sent at least one
 * accepted snapshot). Failures are appended to the rotating error log.
 * The terminal is restored on return and on SIGINT / SIGQUIT / SIGTERM /
 * SIGHUP. */
int pad_play_loop(pid_t pid, int to, int from, int errfd, const PadPlayOpt *o);

#endif
