/* pad_view: blit one Soft snapshot (file or stdin stream) and exit.
 * Soft owns editing; this only draws the last complete SNAP block.
 * No accepted block -> exit 1, draw nothing (fail closed). */
#define _POSIX_C_SOURCE 200809L

#include "snap.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void usage(const char *a0) {
    fprintf(stderr,
            "usage: %s [--ansi|--plain] [--stats] [snapshot-file|-]\n"
            "  reads stdin when no file is given; blits the last complete\n"
            "  Soft SNAP block. Soft owns editing; this only draws.\n",
            a0);
}

int main(int argc, char **argv) {
    const char *path = NULL;
    int mode = -1, stats = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--ansi") == 0)
            mode = 1;
        else if (strcmp(argv[i], "--plain") == 0)
            mode = 0;
        else if (strcmp(argv[i], "--stats") == 0)
            stats = 1;
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
