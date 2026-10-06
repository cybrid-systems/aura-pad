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
 * Soft may mark dirty rows so the interactive viewport redraws less; on
 * a terminal C also compares Soft's previous and new cells to write only
 * what differs (it never decides what a cell holds). Non-SNAP lines
 * between blocks are skipped (Soft logs may share stdout). A bad or
 * truncated block is dropped whole; the last complete one wins.
 *
 * Wire v2 (opt-in, soft/pad/wire2.aura): SNAP v2 pad / GEN g base=b|- /
 * TITLE / CURSOR / SAY / LEGEND / ROWS n= body= / k x (R i, T, H, M) / END.
 * base=- is a full frame (every row 0..n-1 sent once). Otherwise the rows
 * Soft did not send are the rows of the frame with generation b, which
 * must be the last accepted frame and must hold them; body= must equal
 * the byte length of the v1 ROWS body of the rebuilt frame. Any miss
 * drops the block and sets need_full (pad_play asks Soft once for a full
 * frame). The rows sent are Soft's DIRTY set; C never picks rows.
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
    /* wire v2 only */
    int ver;  /* 1 or 2 */
    int gen, base; /* base -1: full frame */
    long body;     /* claimed v1 ROWS body length */
    int row;       /* row index of the current R */
    int nsent;
    unsigned char seen[PAD_MAX_ROWS];
} Block;

/* "R 3" -> 3, or -1. */
static int row_index(const char *line) {
    if (line[0] != 'R' || line[1] != ' ' || line[2] < '0' || line[2] > '9')
        return -1;
    char *end = NULL;
    long v = strtol(line + 2, &end, 10);
    if (*end != '\0' || v < 0 || v >= PAD_MAX_ROWS)
        return -1;
    return (int)v;
}

/* One T/H/M line of row r (shared by v1 and v2). 1 ok, 0 bad. */
static int row_line(PadSnap *s, int r, int sub, const char *line) {
    static const char *tags[3] = {"T", "H", "M"};
    const char *p = payload(line, tags[sub]);
    if (!p)
        return 0;
    size_t n = strlen(p);
    if (n > PAD_MAX_COLS)
        return 0;
    if (sub == 0)
        return (s->t[r] = dup_n(p, n)) != NULL;
    if (!s->t[r] || n != strlen(s->t[r]))
        return 0;
    for (size_t i = 0; i < n; i++)
        if (sub == 1 ? hl_sgr(p[i]) == NULL : !mark_ok(p[i]))
            return 0;
    char *d = dup_n(p, n);
    if (!d)
        return 0;
    if (sub == 1)
        s->h[r] = d;
    else
        s->m[r] = d;
    return 1;
}

/* 1 = consumed, 0 = block is bad, 2 = block complete. */
static int block_line(Block *b, const char *line) {
    PadSnap *s = &b->s;
    const char *p;
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
        if (b->ver == 2) { /* v2: no DIRTY line; the rows sent are the set */
            if (sscanf(line, "ROWS n=%d body=%ld", &b->left, &b->body) != 2 ||
                b->left < 1 || b->left > PAD_MAX_ROWS || b->body < 0)
                return 0;
            s->nrows = b->left; /* slots; unsent ones filled from the base */
            b->stage = 11;
            return 1;
        }
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
    case 5:
        if (!row_line(s, s->nrows, b->sub, line))
            return 0;
        if (++b->sub == 3) {
            b->sub = 0;
            s->nrows++;
            if (--b->left == 0)
                b->stage = 6;
        }
        return 1;
    case 6:
        if (strcmp(line, "END") != 0)
            return 0;
        if (s->cur_line < 0 || s->cur_line >= s->nrows || s->cur_col < 0 ||
            (size_t)s->cur_col > strlen(s->t[s->cur_line]))
            return 0;
        return 2;
    case 10: { /* GEN g base=b | base=- */
        char tail[16];
        if (sscanf(line, "GEN %d base=%15s", &b->gen, tail) != 2 || b->gen < 0)
            return 0;
        if (strcmp(tail, "-") == 0)
            b->base = -1;
        else {
            char *end = NULL;
            long v = strtol(tail, &end, 10);
            if (end == tail || *end != '\0' || v < 0)
                return 0;
            b->base = (int)v;
        }
        b->stage = 0;
        return 1;
    }
    case 11: { /* R i, or END */
        int r = row_index(line);
        if (r >= 0) {
            if (r >= s->nrows || b->seen[r])
                return 0;
            b->seen[r] = 1;
            b->row = r;
            b->sub = 0;
            s->dirty[b->nsent++] = r;
            b->stage = 12;
            return 1;
        }
        if (strcmp(line, "END") != 0)
            return 0;
        return 3; /* complete; rebuilt against the base by the reader */
    }
    case 12:
        if (!row_line(s, b->row, b->sub, line))
            return 0;
        if (++b->sub == 3)
            b->stage = 11;
        return 1;
    }
    return 0;
}

/* v2 END: fill the rows Soft did not send from the base frame, then
 * check what Soft claimed. 1 ok, 0 drop. Copies, never guesses. */
static int v2_finish(Block *b, const PadReader *rd) {
    PadSnap *s = &b->s;
    if (b->base < 0) {
        if (b->nsent != s->nrows)
            return 0; /* a full frame carries every row */
        s->dirty_n = -1;
    } else {
        if (rd->gen < 0 || rd->gen != b->base || rd->accepted == 0)
            return 0; /* not built on the frame C holds */
        const PadSnap *o = &rd->last;
        for (int r = 0; r < s->nrows; r++) {
            if (b->seen[r])
                continue;
            if (r >= o->nrows || !o->t[r] || !o->h[r] || !o->m[r])
                return 0; /* Soft left a row C does not have */
            if (!(s->t[r] = strdup(o->t[r])) || !(s->h[r] = strdup(o->h[r])) ||
                !(s->m[r] = strdup(o->m[r])))
                return 0;
        }
        s->dirty_n = b->nsent;
    }
    long body = 0;
    for (int r = 0; r < s->nrows; r++) {
        if (!s->t[r] || !s->h[r] || !s->m[r])
            return 0;
        body += 3 * (long)strlen(s->t[r]) + 9;
    }
    if (body != b->body)
        return 0;
    if (s->cur_line < 0 || s->cur_line >= s->nrows || s->cur_col < 0 ||
        (size_t)s->cur_col > strlen(s->t[s->cur_line]))
        return 0;
    return 1;
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
    rd->gen = -1;
    rd->block = calloc(1, sizeof(Block));
    return rd->block != NULL;
}

static void reject(PadReader *rd, Block *b) {
    if (b->ver == 2) {
        /* a dropped full frame does not answer the request: ask again,
         * but at most 3 times in a row (a Soft bug must not loop) */
        if (b->base < 0 && ++rd->full_bad < 3)
            rd->asked = 0;
        if (!rd->asked && rd->full_bad < 3)
            rd->need_full = 1;
    }
    block_drop(b);
    rd->rejected++;
    rd->in = 0;
}

int pad_reader_line(PadReader *rd, const char *line) {
    Block *b = (Block *)rd->block;
    int v1 = strcmp(line, "SNAP v1 pad") == 0;
    if (v1 || strcmp(line, "SNAP v2 pad") == 0) {
        if (rd->in)
            reject(rd, b);
        memset(b, 0, sizeof(*b));
        b->s.dirty_n = -1;
        b->ver = v1 ? 1 : 2;
        b->stage = v1 ? 0 : 10;
        rd->in = 1;
        return 0;
    }
    if (!rd->in)
        return 0; /* Soft log line outside a block */
    int rc = block_line(b, line);
    if (rc == 3 && !v2_finish(b, rd))
        rc = 0;
    if (rc == 0) {
        reject(rd, b);
        return 0;
    }
    if (rc == 2 || rc == 3) {
        pad_snap_free(&rd->last);
        rd->last = b->s;
        if (rc == 3) {
            rd->gen = b->gen;
            rd->v2++;
            rd->v2_rows += b->nsent;
            if (b->base < 0) { /* the full frame we asked for (or Soft's own) */
                rd->asked = 0;
                rd->full_bad = 0;
            }
        } else
            rd->gen = -1;
        memset(b, 0, sizeof(*b));
        rd->accepted++;
        rd->in = 0;
        return 1;
    }
    return 0;
}

void pad_reader_finish(PadReader *rd) {
    if (rd->in) /* truncated tail: keep the last accepted block */
        reject(rd, (Block *)rd->block);
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

static int g_force_tty = -1;
void pad_force_tty(int on) { g_force_tty = on; }
static int out_tty(FILE *o) { return g_force_tty >= 0 ? g_force_tty : isatty(fileno(o)); }

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
    if (ansi && out_tty(o))
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

/* Non-tty ANSI stream (tests, pipes): whole dirty rows, no positioning. */
static void blit_dirty_stream(FILE *o, const PadSnap *prev, const PadSnap *s, int ansi) {
    if (strcmp(prev->title, s->title) != 0 || strcmp(prev->say, s->say) != 0 ||
        strcmp(prev->legend, s->legend) != 0 || prev->cur_line != s->cur_line ||
        prev->cur_col != s->cur_col || s->dirty_n > 0) {
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
    fputs("  say: ", o);
    sgr(o, ansi, "1;33");
    fputs(s->say, o);
    sgr(o, ansi, "0");
    fputc('\n', o);
    draw_legend(o, ansi, s->legend);
    fflush(o);
}

/* ---- tty update: Emacs update_frame style, on Soft's own cells ----
 * The screen holds the previous frame Soft sent. C compares that frame's
 * cells with the new frame's cells (letter, HL class, mark, cursor flag)
 * and writes only what differs: per row the span from the first to the
 * last changed cell, "\e[K" when the row got shorter, title/say/legend
 * only when their text changed. A row block shifted by one (a line
 * inserted or deleted above unchanged rows) moves with one insert/delete
 * line inside a scroll region, like Emacs scrolling_window, and only the
 * gutter numbers are rewritten. C never decides what a cell holds. */
enum { GUT = 6 }; /* "%3d | " */

typedef struct {
    const char *t, *h, *m;
    int cur;  /* cursor column on this row, or -1 */
    int num;  /* gutter number shown; -1 blank row, -2 unknown (repaint) */
} RowView;

static RowView row_view(const PadSnap *s, int r) {
    RowView v = {"", "", "", -1, -1};
    if (r < 0 || r >= s->nrows || !s->t[r] || !s->h[r] || !s->m[r])
        return v;
    v.t = s->t[r]; v.h = s->h[r]; v.m = s->m[r];
    v.cur = r == s->cur_line ? s->cur_col : -1;
    v.num = r + 1;
    return v;
}

static size_t row_width(const RowView *v) {
    size_t n = strlen(v->t);
    return (v->cur >= 0 && (size_t)v->cur == n) ? n + 1 : n;
}

/* Cell i of a row as drawn; 0 when past the row's end. */
static int row_cell(const RowView *v, size_t i, char *ch, char *hl, char *mk, int *cur) {
    size_t n = strlen(v->t);
    if (i < n) {
        *ch = v->t[i]; *hl = v->h[i]; *mk = v->m[i];
    } else if (v->cur >= 0 && (size_t)v->cur == n && i == n) {
        *ch = ' '; *hl = '.'; *mk = '.';
    } else
        return 0;
    *cur = v->cur >= 0 && (size_t)v->cur == i;
    return 1;
}

static int cell_same(const RowView *a, const RowView *b, size_t i) {
    char c1 = 0, h1 = 0, m1 = 0, c2 = 0, h2 = 0, m2 = 0;
    int u1 = 0, u2 = 0;
    int p1 = row_cell(a, i, &c1, &h1, &m1, &u1);
    int p2 = row_cell(b, i, &c2, &h2, &m2, &u2);
    if (!p1 || !p2)
        return p1 == p2;
    return c1 == c2 && u1 == u2 && m1 == m2 && (h1 == h2 || hl_sgr(h1) == hl_sgr(h2));
}

static int rows_same_text(const PadSnap *a, int i, const PadSnap *b, int j) {
    if (i < 0 || j < 0 || i >= a->nrows || j >= b->nrows)
        return 0;
    if (!a->t[i] || !b->t[j] || !a->h[i] || !b->h[j] || !a->m[i] || !b->m[j])
        return 0;
    return strcmp(a->t[i], b->t[j]) == 0 && strcmp(a->h[i], b->h[j]) == 0 &&
           strcmp(a->m[i], b->m[j]) == 0;
}

static void draw_gutter(FILE *o, int ansi, int num) {
    sgr(o, ansi, "2");
    fprintf(o, "%3d | ", num);
    sgr(o, ansi, "0");
}

/* Repaint screen row r (0-based, under the title) from old to new. */
static int row_update(FILE *o, int ansi, int r, const RowView *old, const RowView *nw) {
    int wrote = 0;
    RowView blank = {"", "", "", -1, nw->num};
    if (old->num == -2) { /* unknown screen content: whole line */
        fprintf(o, "\033[%d;1H\033[2K", r + 2);
        draw_gutter(o, ansi, nw->num);
        old = &blank;
        wrote = 1;
    } else if (old->num != nw->num) {
        fprintf(o, "\033[%d;1H", r + 2);
        draw_gutter(o, ansi, nw->num);
        wrote = 1;
    }
    size_t wo = row_width(old), wn = row_width(nw);
    size_t w = wo > wn ? wo : wn, a = 0, b = 0;
    int any = 0;
    for (size_t i = 0; i < w; i++)
        if (!cell_same(old, nw, i)) {
            if (!any) a = i;
            b = i;
            any = 1;
        }
    if (!any)
        return wrote;
    fprintf(o, "\033[%d;%dH", r + 2, GUT + 1 + (int)a);
    Attr pen = {NULL, 0, 0};
    for (size_t i = a; i <= b && i < wn; i++) {
        char ch, hl, mk;
        int cur;
        row_cell(nw, i, &ch, &hl, &mk, &cur);
        draw_cell(o, ansi, &pen, ch, hl, mk, cur);
    }
    if (pen.code)
        sgr(o, ansi, "0");
    if (wo > wn && b >= wn)
        fputs("\033[K", o);
    return 1;
}

static void blit_dirty_tty(FILE *o, const PadSnap *prev, const PadSnap *s, int ansi) {
    int np = prev->nrows, nn = s->nrows, wrote = 0;
    if (strcmp(prev->title, s->title) != 0) {
        fputs("\033[H\033[2K", o);
        sgr(o, ansi, "1");
        fprintf(o, "== %s ==", s->title);
        sgr(o, ansi, "0");
        wrote = 1;
    }
    /* Shift detection: first differing row k, then does the rest line up
     * one row down (insert at k) or one row up (delete at k)? */
    int mn = np < nn ? np : nn, k = 0;
    while (k < mn && rows_same_text(prev, k, s, k))
        k++;
    int keep = 0, ins = 0, del = 0;
    for (int i = k; i < mn; i++) keep += rows_same_text(prev, i, s, i);
    if (nn >= np)
        for (int i = k + 1; i < nn; i++) ins += rows_same_text(prev, i - 1, s, i);
    if (nn <= np)
        for (int i = k; i < nn; i++) del += rows_same_text(prev, i + 1, s, i);
    int shift = 0; /* +1 insert line at k, -1 delete line at k */
    if (k < mn && ins >= 2 && ins > keep + 1 && ins >= del) shift = 1;
    else if (k < mn && del >= 2 && del > keep + 1) shift = -1;
    int map[PAD_MAX_ROWS]; /* screen row -> prev row shown there */
    for (int i = 0; i < nn; i++)
        map[i] = i < np ? i : -2;
    if (shift) {
        int bot = (np > nn ? np : nn) + 1; /* last row line, 1-based */
        fprintf(o, "\033[2;%dr\033[%d;1H%s\033[r", bot, k + 2, shift > 0 ? "\033[L" : "\033[M");
        for (int i = k; i < nn; i++) {
            int j = shift > 0 ? (i == k ? -1 : i - 1) : i + 1;
            map[i] = (j >= 0 && j < np) ? j : -1;
        }
        wrote = 1;
    }
    for (int r = 0; r < nn; r++) {
        RowView old = row_view(prev, map[r]);
        if (map[r] == -2) old.num = -2;
        if (map[r] == -1) old.num = -1;
        RowView nw = row_view(s, r);
        wrote |= row_update(o, ansi, r, &old, &nw);
    }
    int moved = np != nn;
    if (moved || strcmp(prev->say, s->say) != 0) {
        fprintf(o, "\033[%d;1H\033[2K  say: ", nn + 2);
        sgr(o, ansi, "1;33");
        fputs(s->say, o);
        sgr(o, ansi, "0");
        wrote = 1;
    }
    if (moved || strcmp(prev->legend, s->legend) != 0) {
        fprintf(o, "\033[%d;1H\033[2K", nn + 3);
        draw_legend(o, ansi, s->legend);
        if (moved)
            fputs("\033[J", o);
        wrote = 1;
    }
    if (wrote) /* park the terminal cursor under the legend, as pad_blit does */
        fprintf(o, "\033[%d;1H", nn + 4);
    fflush(o);
}

void pad_blit_dirty(FILE *o, const PadSnap *prev, const PadSnap *s, int ansi) {
    if (!ansi || !prev || s->dirty_n < 0) {
        pad_blit(o, s, ansi);
        return;
    }
    if (out_tty(o)) {
        if (prev->nrows < 0 || s->nrows > PAD_MAX_ROWS - 4 ||
            (prev->nrows != s->nrows && abs(prev->nrows - s->nrows) > 1)) {
            pad_blit(o, s, ansi);
            return;
        }
        blit_dirty_tty(o, prev, s, ansi);
        return;
    }
    if (prev->nrows != s->nrows) {
        pad_blit(o, s, ansi);
        return;
    }
    blit_dirty_stream(o, prev, s, ansi);
}
