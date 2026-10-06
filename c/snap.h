#ifndef AURA_PAD_SNAP_H
#define AURA_PAD_SNAP_H
/* Soft SNAP v1 / v2 pad: reader + blit. C draws; Soft decides. */
#include <stdio.h>

enum { PAD_MAX_ROWS = 256, PAD_MAX_COLS = 1024, PAD_MAX_TEXT = 512 };

typedef struct {
    char title[PAD_MAX_TEXT];
    char say[PAD_MAX_TEXT];
    char legend[PAD_MAX_TEXT];
    int cur_line, cur_col;
    int nrows;
    char *t[PAD_MAX_ROWS], *h[PAD_MAX_ROWS], *m[PAD_MAX_ROWS];
    /* Optional Soft DIRTY lines=<csv>. dirty_n < 0 means "all rows"
     * (no DIRTY line — full redraw). C never invents dirty sets. */
    int dirty_n;
    int dirty[PAD_MAX_ROWS];
} PadSnap;

typedef struct {
    PadSnap last;  /* last complete, accepted block */
    int accepted;  /* blocks accepted so far */
    int rejected;  /* bad or truncated blocks dropped */
    int in;        /* inside a block */
    void *block;   /* parser scratch */
    /* Wire v2 (SNAP v2 pad): Soft sends only the rows it marked DIRTY on
     * top of the frame with generation base=. C keeps no other state: a
     * delta whose base is not the last accepted frame, or that leaves a
     * row unknown, or whose body length disagrees, is dropped whole and
     * C asks Soft for a full frame (need_full). C never guesses a row. */
    int gen;       /* generation of `last` (-1: v1 frame or none) */
    int need_full; /* a v2 block was dropped: ask Soft once for a full frame */
    int asked;     /* a full-frame request is out; do not ask again */
    int full_bad;  /* full frames dropped in a row (asks stop at 3) */
    int v2;        /* v2 blocks accepted */
    int v2_rows;   /* rows carried by accepted v2 blocks */
} PadReader;

int pad_reader_init(PadReader *rd);
/* Feed one line (no newline). Returns 1 when a new block was accepted. */
int pad_reader_line(PadReader *rd, const char *line);
/* Drop a truncated tail block (counts as rejected). */
void pad_reader_finish(PadReader *rd);
/* Read every line of fp, then finish. Returns 1 if any block accepted. */
int pad_reader_file(PadReader *rd, FILE *fp);
void pad_reader_free(PadReader *rd);

void pad_snap_free(PadSnap *s);
/* Draw s. ansi=1 colors + reverse-video cursor; 0 = plain text + caret. */
void pad_blit(FILE *o, const PadSnap *s, int ansi);
/* Interactive redraw. No prev or no DIRTY: full pad_blit. On a tty:
 * Emacs update_frame style, only the cells that differ between Soft's
 * previous and new frame (plus one insert/delete line for a shifted row
 * block). On a stream: whole rows Soft marked DIRTY or the cursor rows.
 * Never edits Soft's letters — C only chooses which bytes to write. */
void pad_blit_dirty(FILE *o, const PadSnap *prev, const PadSnap *s, int ansi);
/* Treat the output as a terminal (1), a stream (0) or ask isatty (-1).
 * pad_view --replay uses 1 so the tty update path can be checked. */
void pad_force_tty(int on);

#endif
