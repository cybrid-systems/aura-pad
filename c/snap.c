/* aura-pad thin C viewport: SNAP reader + ANSI/plain blit.
 *
 * Soft owns the editor: buffer, cursor, gates, keymap, HL tokenizing, jump
 * marks and every kid word. This module only parses a Soft SNAP block and
 * draws it. An HL letter is a palette index, a mark letter is an underline,
 * SAY/LEGEND are copied as Soft wrote them. No edit state lives here.
 *
 * Wire (see soft/pad/view.aura):
 *   SNAP v1 pad / TITLE / CURSOR line= col= / SAY / LEGEND /
 *   optional DIRTY lines=<csv> / ROWS n=
 *   then n x (T text, H tape, M marks) with |T| == |H| == |M|, then END.
 * Soft may mark dirty rows so the interactive viewport redraws less;
 * C never invents which rows changed. Non-SNAP lines between blocks are
 * skipped (Soft logs may share stdout). A bad or truncated block is
 * dropped whole; the last complete one wins.
 */
#define _POSIX_C_SOURCE 200809L

#include "snap.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

/* Palette only: HL letter -> SGR. Soft decided which letter each cell is. */
static const char *hl_sgr(char k) {
    switch (k) {
    case 'K': return "1;35"; /* magic word: bold magenta */
    case 'S': return "0";    /* name: plain */
    case 'T': return "32";   /* quote: green */
    case 'C': return "2;37"; /* note: dim */
    case 'N': return "33";   /* number: yellow */
    case 'P': return "36";   /* paren: cyan */
    case 'Q': return "1;34"; /* ask (query:): bold blue */
    case 'M': return "1;31"; /* change (mutate:): bold red */
    case '.': return "0";
    default: return NULL;
    }
}

static int mark_ok(char c) { return c == '.' || c == 'd' || c == 'r'; }

void pad_snap_free(PadSnap *s) {
    for (int i = 0; i < s->nrows; i++) {
        free(s->t[i]);
        free(s->h[i]);
        free(s->m[i]);
    }
    memset(s, 0, sizeof(*s));
    s->dirty_n = -1; /* default: all rows dirty when Soft omits DIRTY */
}

static char *dup_n(const char *p, size_t n) {
    char *d = malloc(n + 1);
    if (d) {
        memcpy(d, p, n);
        d[n] = '\0';
    }
    return d;
}

/* "X rest" -> rest (may be empty; "X" alone is an empty payload). */
static const char *payload(const char *line, const char *tag) {
    size_t k = strlen(tag);
    if (strncmp(line, tag, k) != 0)
        return NULL;
    if (line[k] == '\0')
        return line + k;
    if (line[k] != ' ')
        return NULL;
    return line + k + 1;
}

static int copy_field(char *dst, const char *src) {
    size_t n = strlen(src);
    if (n >= PAD_MAX_TEXT)
        return 0;
    memcpy(dst, src, n + 1);
    return 1;
}

/* Parser state for one block. stage: 0 TITLE 1 CURSOR 2 SAY 3 LEGEND
   4 ROWS-or-optional-DIRTY 5 rows (T/H/M cycling) 6 END. */
typedef struct {
    PadSnap s;
    int stage;
    int left; /* rows still expected */
    int sub;  /* 0 T, 1 H, 2 M within the current row */
} Block;

/* 1 = consumed, 0 = block is bad, 2 = block complete. */
static int block_line(Block *b, const char *line) {
    PadSnap *s = &b->s;
    const char *p;
    size_t n;
    switch (b->stage) {
    case 0:
        if (!(p = payload(line, "TITLE")) || !copy_field(s->title, p))
            return 0;
        b->stage = 1;
        return 1;
    case 1:
        if (sscanf(line, "CURSOR line=%d col=%d", &s->cur_line, &s->cur_col) != 2)
            return 0;
        b->stage = 2;
        return 1;
    case 2:
        if (!(p = payload(line, "SAY")) || !copy_field(s->say, p))
            return 0;
        b->stage = 3;
        return 1;
    case 3:
        if (!(p = payload(line, "LEGEND")) || !copy_field(s->legend, p))
            return 0;
        b->stage = 4;
        return 1;
    case 4:
        /* Optional Soft DIRTY lines=0,2,5 — stay in stage 4 until ROWS. */
        if (strncmp(line, "DIRTY lines=", 12) == 0) {
            const char *q = line + 12;
            s->dirty_n = 0;
            while (*q && s->dirty_n < PAD_MAX_ROWS) {
                char *end = NULL;
                long v = strtol(q, &end, 10);
                if (end == q || v < 0 || v >= PAD_MAX_ROWS)
                    return 0;
                s->dirty[s->dirty_n++] = (int)v;
                if (*end == ',')
                    q = end + 1;
                else if (*end == '\0')
                    break;
                else
                    return 0;
            }
            return 1;
        }
        if (sscanf(line, "ROWS n=%d", &b->left) != 1 || b->left < 1 ||
            b->left > PAD_MAX_ROWS)
            return 0;
        s->nrows = 0; /* counts rows fully read (T, H and M) */
        b->sub = 0;
        b->stage = 5;
        return 1;
    case 5: {
        static const char *tags[3] = {"T", "H", "M"};
        if (!(p = payload(line, tags[b->sub])))
            return 0;
        n = strlen(p);
        if (n > PAD_MAX_COLS)
            return 0;
        int r = s->nrows;
        if (b->sub == 0) {
            if (!(s->t[r] = dup_n(p, n)))
                return 0;
        } else {
            if (n != strlen(s->t[r]))
                return 0;
            for (size_t i = 0; i < n; i++) {
                if (b->sub == 1 ? hl_sgr(p[i]) == NULL : !mark_ok(p[i]))
                    return 0;
            }
            char *d = dup_n(p, n);
            if (!d)
                return 0;
            if (b->sub == 1)
                s->h[r] = d;
            else
                s->m[r] = d;
        }
        if (++b->sub == 3) {
            b->sub = 0;
            s->nrows++;
            if (--b->left == 0)
                b->stage = 6;
        }
        return 1;
    }
    case 6:
        if (strcmp(line, "END") != 0)
            return 0;
        if (s->cur_line < 0 || s->cur_line >= s->nrows || s->cur_col < 0 ||
            (size_t)s->cur_col > strlen(s->t[s->cur_line]))
            return 0;
        return 2;
    }
    return 0;
}

/* Free a partially-built block (rows may be half filled). */
static void block_drop(Block *b) {
    PadSnap *s = &b->s;
    int r = s->nrows;
    if (b->stage == 5 && r < PAD_MAX_ROWS) {
        free(s->t[r]);
        free(s->h[r]);
        free(s->m[r]);
    }
    pad_snap_free(s);
    memset(b, 0, sizeof(*b));
}

/* Incremental reader: feed one line at a time (stream or file). */
int pad_reader_init(PadReader *rd) {
    memset(rd, 0, sizeof(*rd));
    rd->block = calloc(1, sizeof(Block));
    return rd->block != NULL;
}

int pad_reader_line(PadReader *rd, const char *line) {
    Block *b = (Block *)rd->block;
    if (strcmp(line, "SNAP v1 pad") == 0) {
        if (rd->in) {
            block_drop(b);
            rd->rejected++;
        }
        memset(b, 0, sizeof(*b));
        b->s.dirty_n = -1;
        rd->in = 1;
        return 0;
    }
    if (!rd->in)
        return 0; /* Soft log line outside a block */
    int rc = block_line(b, line);
    if (rc == 0) {
        block_drop(b);
        rd->rejected++;
        rd->in = 0;
        return 0;
    }
    if (rc == 2) {
        pad_snap_free(&rd->last);
        rd->last = b->s;
        memset(b, 0, sizeof(*b));
        rd->accepted++;
        rd->in = 0;
        return 1;
    }
    return 0;
}

void pad_reader_finish(PadReader *rd) {
    if (rd->in) { /* truncated tail: keep the last accepted block */
        block_drop((Block *)rd->block);
        rd->rejected++;
        rd->in = 0;
    }
}

void pad_reader_free(PadReader *rd) {
    pad_reader_finish(rd);
    pad_snap_free(&rd->last);
    free(rd->block);
    rd->block = NULL;
}

int pad_reader_file(PadReader *rd, FILE *fp) {
    char *line = NULL;
    size_t cap = 0;
    ssize_t got;
    while ((got = getline(&line, &cap, fp)) >= 0) {
        while (got > 0 && (line[got - 1] == '\n' || line[got - 1] == '\r'))
            line[--got] = '\0';
        pad_reader_line(rd, line);
    }
    free(line);
    pad_reader_finish(rd);
    return rd->accepted > 0;
}

/* ---- drawing: pure copy of Soft's decisions ---- */

static void sgr(FILE *o, int ansi, const char *code) {
    if (ansi)
        fprintf(o, "\033[%sm", code);
}

/* One SGR per run of equal (hl, mark, cursor) cells: a blit, not a lexer. */
typedef struct {
    const char *code; /* palette entry, so '.' and 'S' share a run */
    char mk;
    int cur;
} Attr;

static void draw_cell(FILE *o, int ansi, Attr *pen, char ch, char hl, char mk,
                      int cursor) {
    const char *code = hl_sgr(hl);
    if (ansi && (pen->code == NULL || strcmp(pen->code, code) != 0 ||
                 pen->mk != mk || pen->cur != cursor)) {
        fprintf(o, "\033[0;%s", code);
        if (mk == 'd')
            fputs(";1;4", o);
        else if (mk == 'r')
            fputs(";4", o);
        if (cursor)
            fputs(";7", o);
        fputc('m', o);
        pen->code = code;
        pen->mk = mk;
        pen->cur = cursor;
    }
    fputc(ch, o);
}

static void draw_legend(FILE *o, int ansi, const char *legend) {
    const char *p = legend;
    fputs("  key: ", o);
    while (*p) {
        const char *sp = strchr(p, ' ');
        size_t n = sp ? (size_t)(sp - p) : strlen(p);
        if (ansi && n > 2 && p[1] == '=') {
            char k = p[0];
            if (k == 'd' || k == 'r')
                sgr(o, ansi, k == 'd' ? "1;4" : "4");
            else if (hl_sgr(k))
                sgr(o, ansi, hl_sgr(k));
            fwrite(p + 2, 1, n - 2, o);
            sgr(o, ansi, "0");
        } else {
            fwrite(p, 1, n, o);
        }
        if (!sp)
            break;
        fputc(' ', o);
        p = sp + 1;
    }
    fputc('\n', o);
}

void pad_blit(FILE *o, const PadSnap *s, int ansi) {
    if (ansi && isatty(fileno(o)))
        fputs("\033[2J\033[H", o);
    sgr(o, ansi, "1");
    fprintf(o, "== %s ==", s->title);
    sgr(o, ansi, "0");
    fputc('\n', o);
    for (int r = 0; r < s->nrows; r++) {
        const char *t = s->t[r], *h = s->h[r], *m = s->m[r];
        size_t n = strlen(t);
        sgr(o, ansi, "2");
        fprintf(o, "%3d | ", r + 1);
        sgr(o, ansi, "0");
        Attr pen = {NULL, 0, 0};
        for (size_t i = 0; i < n; i++)
            draw_cell(o, ansi, &pen, t[i], h[i], m[i],
                      r == s->cur_line && (int)i == s->cur_col);
        if (r == s->cur_line && (size_t)s->cur_col == n)
            draw_cell(o, ansi, &pen, ' ', '.', '.', 1);
        sgr(o, ansi, "0");
        fputc('\n', o);
        if (!ansi && r == s->cur_line) {
            /* plain mode: caret under the cursor cell, marks under names */
            fprintf(o, "    | %*s^\n", s->cur_col, "");
        }
        if (!ansi && strspn(m, ".") != n) /* any d/r mark on this row */
            fprintf(o, "    | %s\n", m);
    }
    fputs("  say: ", o);
    sgr(o, ansi, "1;33");
    fputs(s->say, o);
    sgr(o, ansi, "0");
    fputc('\n', o);
    draw_legend(o, ansi, s->legend);
    fflush(o);
}

/* Interactive dirty redraw. Soft said which rows changed; C only paints.
 * Falls back to full pad_blit when Soft omitted DIRTY or prev is missing. */
static int row_dirty(const PadSnap *s, int r) {
    if (s->dirty_n < 0)
        return 1;
    for (int i = 0; i < s->dirty_n; i++)
        if (s->dirty[i] == r)
            return 1;
    return 0;
}

void pad_blit_dirty(FILE *o, const PadSnap *prev, const PadSnap *s, int ansi) {
    if (!ansi || !prev || s->dirty_n < 0 || prev->nrows != s->nrows) {
        pad_blit(o, s, ansi);
        return;
    }
    /* Home without wipe; redraw title when Soft changed it. */
    if (isatty(fileno(o)))
        fputs("\033[H", o);
    if (strcmp(prev->title, s->title) != 0 || strcmp(prev->say, s->say) != 0 ||
        strcmp(prev->legend, s->legend) != 0 || prev->cur_line != s->cur_line ||
        prev->cur_col != s->cur_col || s->dirty_n > 0) {
        /* Title line always refreshed so keys=/say stay honest. */
        if (isatty(fileno(o)))
            fputs("\033[H\033[2K", o);
        sgr(o, ansi, "1");
        fprintf(o, "== %s ==", s->title);
        sgr(o, ansi, "0");
        fputc('\n', o);
    }
    for (int r = 0; r < s->nrows; r++) {
        int need = row_dirty(s, r) || r == s->cur_line || r == prev->cur_line;
        if (!need && prev->t[r] && s->t[r] && strcmp(prev->t[r], s->t[r]) == 0 &&
            prev->h[r] && s->h[r] && strcmp(prev->h[r], s->h[r]) == 0 &&
            prev->m[r] && s->m[r] && strcmp(prev->m[r], s->m[r]) == 0)
            continue;
        if (isatty(fileno(o)))
            fprintf(o, "\033[%d;1H\033[2K", r + 2); /* +1 title, 1-based */
        const char *tt = s->t[r], *hh = s->h[r], *mm = s->m[r];
        size_t n = strlen(tt);
        sgr(o, ansi, "2");
        fprintf(o, "%3d | ", r + 1);
        sgr(o, ansi, "0");
        Attr pen = {NULL, 0, 0};
        for (size_t i = 0; i < n; i++)
            draw_cell(o, ansi, &pen, tt[i], hh[i], mm[i],
                      r == s->cur_line && (int)i == s->cur_col);
        if (r == s->cur_line && (size_t)s->cur_col == n)
            draw_cell(o, ansi, &pen, ' ', '.', '.', 1);
        sgr(o, ansi, "0");
        fputc('\n', o);
    }
    /* say + legend under the rows */
    if (isatty(fileno(o)))
        fprintf(o, "\033[%d;1H\033[J", s->nrows + 2);
    fputs("  say: ", o);
    sgr(o, ansi, "1;33");
    fputs(s->say, o);
    sgr(o, ansi, "0");
    fputc('\n', o);
    draw_legend(o, ansi, s->legend);
    fflush(o);
}
