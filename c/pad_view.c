/* pad_view: blit one Soft snapshot (file or stdin stream) and exit.
 * Soft owns editing; this only draws the last complete SNAP block.
 * No accepted block -> exit 1, draw nothing (fail closed). */
#define _POSIX_C_SOURCE 200809L

#include "snap.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Every accepted block, drawn the way pad_play draws it on a terminal. */
static int replay_stream(PadReader *rd, FILE *fp, int full) {
    PadSnap prev;
    memset(&prev, 0, sizeof(prev));
    int have = 0, frames = 0;
    char *line = NULL;
    size_t cap = 0;
    ssize_t got;
    pad_force_tty(1);
    while ((got = getline(&line, &cap, fp)) >= 0) {
        while (got > 0 && (line[got - 1] == '\n' || line[got - 1] == '\r'))
            line[--got] = '\0';
        if (!pad_reader_line(rd, line))
            continue;
        if (full)
            pad_blit(stdout, &rd->last, 1);
        else
            pad_blit_dirty(stdout, have ? &prev : NULL, &rd->last, 1);
        fputs("\033]pad-frame\007", stdout);
        fflush(stdout);
        pad_snap_free(&prev);
        prev = rd->last;
        for (int r = 0; r < prev.nrows; r++) {
            prev.t[r] = prev.t[r] ? strdup(prev.t[r]) : NULL;
            prev.h[r] = prev.h[r] ? strdup(prev.h[r]) : NULL;
            prev.m[r] = prev.m[r] ? strdup(prev.m[r]) : NULL;
        }
        have = 1;
        frames++;
    }
    free(line);
    pad_reader_finish(rd);
    pad_snap_free(&prev);
    return frames;
}

static void usage(const char *a0) {
    fprintf(stderr,
            "usage: %s [--ansi|--plain] [--stats] [--replay|--replay-full] [snapshot-file|-]\n"
            "  reads stdin when no file is given; blits the last complete\n"
            "  Soft SNAP block. Soft owns editing; this only draws.\n"
            "  --replay draws every block as pad_play does on a terminal\n"
            "  (cell diff against the previous block); --replay-full\n"
            "  repaints each block. Each frame ends with ESC ] pad-frame BEL.\n",
            a0);
}

int main(int argc, char **argv) {
    const char *path = NULL;
    int mode = -1, stats = 0, replay = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--ansi") == 0)
            mode = 1;
        else if (strcmp(argv[i], "--plain") == 0)
            mode = 0;
        else if (strcmp(argv[i], "--stats") == 0)
            stats = 1;
        else if (strcmp(argv[i], "--replay") == 0)
            replay = 1;
        else if (strcmp(argv[i], "--replay-full") == 0)
            replay = 2;
        else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else if (argv[i][0] == '-' && argv[i][1] != '\0') {
            usage(argv[0]);
            return 2;
        } else if (!path)
            path = argv[i];
        else {
            usage(argv[0]);
            return 2;
        }
    }
    if (mode < 0)
        mode = isatty(STDOUT_FILENO) && getenv("NO_COLOR") == NULL;

    FILE *fp = stdin;
    if (path && strcmp(path, "-") != 0) {
        fp = fopen(path, "r");
        if (!fp) {
            fprintf(stderr, "pad_view: cannot open %s\n", path);
            return 1;
        }
    }
    PadReader rd;
    if (!pad_reader_init(&rd)) {
        fprintf(stderr, "pad_view: out of memory\n");
        return 1;
    }
    if (replay) {
        int frames = replay_stream(&rd, fp, replay == 2);
        if (fp != stdin)
            fclose(fp);
        pad_reader_free(&rd);
        if (stats)
            fprintf(stderr, "PAD_C_REPLAY frames=%d mode=%s\n", frames,
                    replay == 2 ? "full" : "diff");
        return frames > 0 ? 0 : 1;
    }
    int ok = pad_reader_file(&rd, fp);
    if (fp != stdin)
        fclose(fp);
    if (!ok) {
        fprintf(stderr, "pad_view: no accepted snapshot (rejected=%d)\n",
                rd.rejected);
        pad_reader_free(&rd);
        return 1;
    }
    const PadSnap *s = &rd.last;
    pad_blit(stdout, s, mode);
    if (stats) {
        int cells = 0, marks = 0;
        for (int r = 0; r < s->nrows; r++) {
            cells += (int)strlen(s->t[r]);
            for (const char *q = s->m[r]; *q; q++)
                marks += *q != '.';
        }
        fprintf(stderr,
                "PAD_C_BLIT rows=%d cells=%d cursor=%d:%d marks=%d snaps=%d "
                "rejected=%d mode=%s\n",
                s->nrows, cells, s->cur_line, s->cur_col, marks, rd.accepted,
                rd.rejected, mode ? "ansi" : "plain");
    }
    pad_reader_free(&rd);
    return 0;
}
