#ifndef AURA_PAD_SNAP_H
#define AURA_PAD_SNAP_H
/* Soft SNAP v1 pad: reader + blit. C draws; Soft decides. */
#include <stdio.h>

enum { PAD_MAX_ROWS = 256, PAD_MAX_COLS = 1024, PAD_MAX_TEXT = 512 };

typedef struct {
    char title[PAD_MAX_TEXT];
    char say[PAD_MAX_TEXT];
    char legend[PAD_MAX_TEXT];
    int cur_line, cur_col;
    int nrows;
    char *t[PAD_MAX_ROWS], *h[PAD_MAX_ROWS], *m[PAD_MAX_ROWS];
} PadSnap;

typedef struct {
    PadSnap last;  /* last complete, accepted block */
    int accepted;  /* blocks accepted so far */
    int rejected;  /* bad or truncated blocks dropped */
    int in;        /* inside a block */
    void *block;   /* parser scratch */
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

#endif
