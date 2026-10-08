/* aura-pad: the one-command editor. `aura-pad [FILE]`, like vi or emacs.
 *
 * C here only launches and blits. It finds the Aura Soft runtime and the
 * pad's Soft files, starts Soft directly (fork + exec, no shell, no
 * script) on soft/pad/play.aura with the environment the pad needs, and
 * runs the shared viewport loop (play_loop.c). Soft owns everything
 * else: the keymap, the buffer, opening and saving FILE (PAD_FILE), and
 * every word on the screen.
 *
 * Soft runtime, first match wins:
 *   $AURA_BIN, `aura` on PATH, /workspace/aura-grok/build/aura,
 *   ~/code/grok-dev/aura-grok/build/aura,
 *   /home/dev/code/grok-dev/aura-grok/build/aura
 * A candidate must start here (`aura --help`, or `aura -e 0` when no
 * std module dir is found); one built for another libc does not.
 * Module path: $AURA_PATH, else $AURA_HOME/lib, else ../lib next to the
 * binary's build dir.
 * Pad Soft files (soft/pad/play.aura): $AURA_PAD_HOME, else the share dir
 * baked in at build time (AURA_PAD_SHARE), else next to this binary
 * (../share/aura-pad, or the source tree for out/c/aura-pad).
 * No runnable aura: docker fallback (docker run ... dev:v1.0.9 with the
 * aura build dir mounted), exec'd directly, with a one-line notice. Off
 * with AURA_PAD_NO_DOCKER=1. Nothing found: a clear message, exit 127. */
#define _XOPEN_SOURCE 700

#include "play_loop.h"
#include "errlog.h"

#include <errno.h>
#include <stdarg.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef AURA_PAD_SHARE
#define AURA_PAD_SHARE ""
#endif
#ifndef AURA_PAD_VERSION
#define AURA_PAD_VERSION "0.1"
#endif
#define DOCKER_IMAGE "ghcr.io/cybrid-systems/dev:v1.0.9"
#define BOX_AURA_SRC "/workspace/aura-grok"

typedef struct {
    char soft[PATH_MAX];      /* aura binary (native) */
    char aura_path[PATH_MAX]; /* module path for AURA_PATH ("" = leave) */
    char home[PATH_MAX];      /* pad home: has soft/pad/play.aura */
    char file[PATH_MAX];      /* absolute FILE path, "" = none */
    char docker[PATH_MAX];    /* docker binary when mode is docker */
    char src[PATH_MAX];       /* aura source/build root for docker */
    int use_sudo;             /* docker socket not writable: sudo -n */
    int docker_mode;
    int rows, cols;           /* tty text area; 0 = Soft picks a tall default */
} Launch;

/* snprintf that says whether it fit */
static int fmt(char *out, size_t n, const char *f, ...) {
    va_list ap;
    va_start(ap, f);
    int k = vsnprintf(out, n, f, ap);
    va_end(ap);
    return k >= 0 && (size_t)k < n;
}

static int is_exec(const char *p) {
    struct stat st;
    return p && *p && stat(p, &st) == 0 && S_ISREG(st.st_mode) && access(p, X_OK) == 0;
}

static int is_dir(const char *p) {
    struct stat st;
    return p && *p && stat(p, &st) == 0 && S_ISDIR(st.st_mode);
}

static int join(char *out, size_t n, const char *a, const char *b) {
    int k = fmt(out, n, "%s/%s", a, b);
    return k > 0 && (size_t)k < n;
}

static int has_play(const char *home) {
    char p[PATH_MAX];
    struct stat st;
    return join(p, sizeof(p), home, "soft/pad/play.aura") && stat(p, &st) == 0;
}

/* dirname in place ("/a/b/c" -> "/a/b"; "/a" -> "/") */
static void up(char *p) {
    char *s = strrchr(p, '/');
    if (!s) { strcpy(p, "."); return; }
    if (s == p) s[1] = '\0';
    else *s = '\0';
}

static int on_path(const char *name, char *out, size_t n) {
    const char *path = getenv("PATH");
    if (!path || !*path)
        return 0;
    const char *p = path;
    while (*p) {
        const char *c = strchr(p, ':');
        size_t len = c ? (size_t)(c - p) : strlen(p);
        if (len > 0 && len < PATH_MAX) {
            char dir[PATH_MAX];
            memcpy(dir, p, len);
            dir[len] = '\0';
            if (join(out, n, dir, name) && is_exec(out))
                return 1;
        }
        if (!c) break;
        p = c + 1;
    }
    return 0;
}

/* Does this aura start on this machine, with the env the pad gives it?
 * A binary built for another libc fails in the loader, so `aura --help`
 * (~10 ms) is enough when AURA_PATH holds the std modules (std/INDEX.aura);
 * with no lib dir found we run the full `aura -e 0` (~100 ms), which
 * also loads the std prelude. Output is dropped. */
static int starts(const char *aura, const char *aura_path) {
    char idx[PATH_MAX];
    int quick = aura_path && *aura_path && join(idx, sizeof(idx), aura_path, "std/INDEX.aura") &&
                access(idx, R_OK) == 0;
    pid_t pid = fork();
    if (pid < 0)
        return 0;
    if (pid == 0) {
        int dn = open("/dev/null", O_RDWR);
        if (dn >= 0) {
            dup2(dn, STDIN_FILENO);
            dup2(dn, STDOUT_FILENO);
            dup2(dn, STDERR_FILENO);
        }
        if (aura_path && *aura_path) setenv("AURA_PATH", aura_path, 1);
        setenv("AURA_PIPELINE_STRICT", "0", 1);
        setenv("AURA_SANDBOX", "off", 1);
        if (quick)
            execl(aura, aura, "--help", (char *)NULL);
        else
            execl(aura, aura, "-e", "0", (char *)NULL);
        _exit(127);
    }
    int st = 0;
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {}
    return WIFEXITED(st) && WEXITSTATUS(st) == 0;
}

/* Candidate aura binaries in order. Returns the count written. */
static int candidates(char out[][PATH_MAX], int max) {
    int n = 0;
    const char *e = getenv("AURA_BIN");
    if (e && *e && n < max) fmt(out[n++], PATH_MAX, "%s", e);
    if (n < max && on_path("aura", out[n], PATH_MAX)) n++;
    if (n < max) fmt(out[n++], PATH_MAX, "%s", BOX_AURA_SRC "/build/aura");
    const char *h = getenv("HOME");
    if (h && *h && n < max) fmt(out[n++], PATH_MAX, "%s/code/grok-dev/aura-grok/build/aura", h);
    if (n < max) fmt(out[n++], PATH_MAX, "%s", "/home/dev/code/grok-dev/aura-grok/build/aura");
    return n;
}

static void find_aura_path(Launch *L) {
    const char *e = getenv("AURA_PATH");
    if (e && *e) { fmt(L->aura_path, sizeof(L->aura_path), "%s", e); return; }
    const char *ah = getenv("AURA_HOME");
    char p[PATH_MAX];
    if (ah && *ah && join(p, sizeof(p), ah, "lib") && is_dir(p)) {
        fmt(L->aura_path, sizeof(L->aura_path), "%s", p);
        return;
    }
    char r[PATH_MAX];
    if (realpath(L->soft, r)) { /* <root>/build/aura -> <root>/lib */
        up(r);
        up(r);
        if (join(p, sizeof(p), r, "lib") && is_dir(p)) {
            fmt(L->aura_path, sizeof(L->aura_path), "%s", p);
            return;
        }
    }
    L->aura_path[0] = '\0';
}

static int find_home(Launch *L) {
    const char *e = getenv("AURA_PAD_HOME");
    if (e && *e) {
        if (has_play(e) && realpath(e, L->home)) return 1;
        fprintf(stderr, "aura-pad: AURA_PAD_HOME=%s has no soft/pad/play.aura\n", e);
        pad_errlog_msg("aura-pad", "AURA_PAD_HOME has no soft/pad/play.aura");
        return 0;
    }
    if (AURA_PAD_SHARE[0] && has_play(AURA_PAD_SHARE) && realpath(AURA_PAD_SHARE, L->home))
        return 1;
    char exe[PATH_MAX];
    ssize_t k = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (k > 0) {
        exe[k] = '\0';
        up(exe); /* bin dir */
        char p[PATH_MAX];
        if (join(p, sizeof(p), exe, "../share/aura-pad") && has_play(p) && realpath(p, L->home))
            return 1;
        if (join(p, sizeof(p), exe, "../..") && has_play(p) && realpath(p, L->home))
            return 1; /* source tree: out/c/aura-pad */
    }
    return 0;
}

/* Absolute FILE path. Existing: realpath (so Soft's no-follow open sees
 * the real file). New: real folder + name. Missing folder: cwd + FILE,
 * and Soft will say it cannot save there. */
static void resolve_file(const char *arg, char *out, size_t n) {
    char r[PATH_MAX];
    if (realpath(arg, r)) { fmt(out, n, "%s", r); return; }
    char dir[PATH_MAX];
    fmt(dir, sizeof(dir), "%s", arg);
    const char *base = strrchr(arg, '/');
    base = base ? base + 1 : arg;
    if (strchr(arg, '/')) up(dir); else strcpy(dir, ".");
    if (realpath(dir, r)) { fmt(out, n, "%s/%s", strcmp(r, "/") == 0 ? "" : r, base); return; }
    if (arg[0] == '/') { fmt(out, n, "%s", arg); return; }
    char cwd[PATH_MAX];
    if (getcwd(cwd, sizeof(cwd))) fmt(out, n, "%s/%s", cwd, arg);
    else fmt(out, n, "%s", arg);
}

static int find_docker(Launch *L, char cand[][PATH_MAX], int nc) {
    const char *off = getenv("AURA_PAD_NO_DOCKER");
    if (off && *off && strcmp(off, "0") != 0)
        return 0;
    if (!on_path("docker", L->docker, sizeof(L->docker)))
        return 0;
    /* an aura build tree to mount: $AURA_SRC, else a candidate's root */
    const char *s = getenv("AURA_SRC");
    if (s && *s && is_dir(s)) {
        fmt(L->src, sizeof(L->src), "%s", s);
    } else {
        L->src[0] = '\0';
        for (int i = 0; i < nc && !L->src[0]; i++) {
            char r[PATH_MAX];
            if (is_exec(cand[i]) && realpath(cand[i], r)) {
                up(r);
                up(r);
                fmt(L->src, sizeof(L->src), "%s", r);
            }
        }
    }
    if (!L->src[0])
        return 0;
    char sudo[PATH_MAX];
    L->use_sudo = access("/var/run/docker.sock", W_OK) != 0 && on_path("sudo", sudo, sizeof(sudo));
    return 1;
}

/* Direct play.aura, with no launcher, still sees this. aura-pad itself
 * does not inject it. PAD_VI=0 is the old modeless map. */
static const char *vi_flag(void) {
    const char *v = getenv("PAD_VI");
    if (v && *v)
        return v;
    return "1";
}

/* PAD_CLASSIC=1 is today's vi. Anything else is the sentence line. */
static int classic_on(void) {
    const char *v = getenv("PAD_CLASSIC");
    return v && strcmp(v, "1") == 0;
}

/* Mutate type gate. An external value, including soft, is kept.
 * Empty or unset becomes hard. Callers only pass the string on.
 * They do not compare it. */
static const char *type_gate(void) {
    const char *v = getenv("AURA_MUTATE_TYPE_GATE");
    if (v && *v)
        return v;
    return "hard";
}

static void child_env(const Launch *L) {
    if (L->aura_path[0]) setenv("AURA_PATH", L->aura_path, 1);
    setenv("AURA_PIPELINE_STRICT", "0", 1);
    setenv("AURA_SANDBOX", "off", 1);
    setenv("AURA_BIN", L->soft, 1);
    setenv("AURA_PAD_HOME", L->home, 1);
    if (classic_on()) {
        setenv("PAD_VI", "1", 1);
        unsetenv("PAD_SENTENCE");
    } else {
        setenv("PAD_SENTENCE", "1", 1);
        /* Do not leave PAD_VI=1 in the child. An explicit 0 stays. */
        if (strcmp(vi_flag(), "1") == 0)
            unsetenv("PAD_VI");
    }
    /* Copy first. setenv may rewrite the block getenv still points at.
     * A failed copy leaves an external value alone. */
    {
        const char *g = type_gate();
        size_t n = strlen(g);
        char *gate = malloc(n + 1);
        if (gate) {
            memcpy(gate, g, n + 1);
            setenv("AURA_MUTATE_TYPE_GATE", gate, 1);
            free(gate);
        }
    }
    if (L->rows > 0) {
        char b[16];
        snprintf(b, sizeof b, "%d", L->rows);
        setenv("PAD_ROWS", b, 1);
    }
    if (L->cols > 0) {
        char b[16];
        snprintf(b, sizeof b, "%d", L->cols);
        setenv("PAD_COLS", b, 1);
    }
    if (L->file[0]) setenv("PAD_FILE", L->file, 1);
    else unsetenv("PAD_FILE");
}

/* argv for the Soft child; strings live in st (big enough) */
static int build_argv(const Launch *L, char *argv[], int max, char st[][2 * PATH_MAX + 64]) {
    int a = 0, s = 0;
    char play[PATH_MAX + 32];
    fmt(play, sizeof(play), "%s/soft/pad/play.aura", L->home);
    if (!L->docker_mode) {
        argv[a++] = (char *)L->soft;
        fmt(st[s], sizeof(st[s]), "%s", play); argv[a++] = st[s++];
        argv[a] = NULL;
        return a;
    }
    if (L->use_sudo) { argv[a++] = "sudo"; argv[a++] = "-n"; }
    argv[a++] = (char *)L->docker;
    argv[a++] = "run"; argv[a++] = "--rm"; argv[a++] = "-i";
    argv[a++] = "--entrypoint"; argv[a++] = "/usr/local/bin/gosu";
    argv[a++] = "-v"; fmt(st[s], sizeof(st[s]), "%s:" BOX_AURA_SRC, L->src); argv[a++] = st[s++];
    argv[a++] = "-v"; fmt(st[s], sizeof(st[s]), "%s:%s:ro", L->home, L->home); argv[a++] = st[s++];
    if (L->file[0]) {
        char dir[PATH_MAX];
        fmt(dir, sizeof(dir), "%s", L->file);
        up(dir);
        if (is_dir(dir)) {
            argv[a++] = "-v"; fmt(st[s], sizeof(st[s]), "%s:%s", dir, dir); argv[a++] = st[s++];
        }
        argv[a++] = "-e"; fmt(st[s], sizeof(st[s]), "PAD_FILE=%s", L->file); argv[a++] = st[s++];
    }
    argv[a++] = "-e"; argv[a++] = "AURA_PATH=" BOX_AURA_SRC "/lib";
    argv[a++] = "-e"; argv[a++] = "AURA_PIPELINE_STRICT=0";
    argv[a++] = "-e"; argv[a++] = "AURA_SANDBOX=off";
    argv[a++] = "-e"; argv[a++] = "AURA_BIN=" BOX_AURA_SRC "/build/aura";
    argv[a++] = "-e"; fmt(st[s], sizeof(st[s]), "AURA_PAD_HOME=%s", L->home); argv[a++] = st[s++];
    if (classic_on()) {
        argv[a++] = "-e"; argv[a++] = "PAD_VI=1";
    } else {
        argv[a++] = "-e"; argv[a++] = "PAD_SENTENCE=1";
        if (strcmp(vi_flag(), "0") == 0) {
            argv[a++] = "-e"; argv[a++] = "PAD_VI=0";
        }
    }
    argv[a++] = "-e"; fmt(st[s], sizeof(st[s]), "AURA_MUTATE_TYPE_GATE=%s", type_gate()); argv[a++] = st[s++];
    if (L->rows > 0) {
        argv[a++] = "-e";
        fmt(st[s], sizeof(st[s]), "PAD_ROWS=%d", L->rows);
        argv[a++] = st[s++];
    }
    if (L->cols > 0) {
        argv[a++] = "-e";
        fmt(st[s], sizeof(st[s]), "PAD_COLS=%d", L->cols);
        argv[a++] = st[s++];
    }
    const char *img = getenv("AURA_PAD_IMAGE");
    argv[a++] = (char *)(img && *img ? img : DOCKER_IMAGE);
    argv[a++] = "dev";
    argv[a++] = BOX_AURA_SRC "/build/aura";
    fmt(st[s], sizeof(st[s]), "%s", play); argv[a++] = st[s++];
    argv[a] = NULL;
    (void)max;
    return a;
}

static void close2(int p[2]) {
    if (p[0] >= 0) close(p[0]);
    if (p[1] >= 0) close(p[1]);
}

static pid_t spawn(const Launch *L, char *argv[], int *to_fd, int *from_fd, int *err_fd) {
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
        if (!L->docker_mode) child_env(L);
        execvp(argv[0], argv);
        fprintf(stderr, "aura-pad: cannot run %s: %s\n", argv[0], strerror(errno));
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

static void usage(void) {
    fprintf(stderr,
            "usage: aura-pad [FILE]\n"
            "  Opens FILE in the aura pad (a new page if it does not exist yet).\n"
            "  The sentence line is the default. Tab reaches it. save and quit are sentences.\n"
            "  PAD_CLASSIC=1 starts in vi normal mode: i types, a appends, Esc returns.\n"
            "  Arrows, hjkl, and ctrl-b/f/p/n move in either mode.\n"
            "  ctrl-x ctrl-s saves, ctrl-q (or ctrl-x ctrl-c) quits.\n"
            "  dd deletes a line. :eval (or alt-x, then enter) runs the page.\n"
            "  The screen follows the terminal, and the buffer scrolls.\n"
            "  ctrl-g cancels. ctrl-x ctrl-f opens a file. alt-f, alt-b, alt-d\n"
            "  move or delete a word. M-x search finds text.\n"
            "  ctrl-\\ is the emergency exit (nothing is saved).\n"
            "  PAD_VI=0 keeps the old modeless keys.\n"
            "options: --plain|--ansi  --wire1|--wire2  --where (show what would run)\n"
            "         --version  -h|--help\n"
            "env: AURA_BIN, AURA_PATH, AURA_HOME, AURA_PAD_HOME, AURA_PAD_NO_DOCKER=1,\n"
            "     AURA_SRC, AURA_PAD_IMAGE (docker fallback), PAD_VI,\n"
            "     AURA_PAD_LOG, AURA_PAD_LOG_MAX (rotating error log)\n");
}

int main(int argc, char **argv) {
    PadPlayOpt o = {"aura-pad", -1, 0, 0, 1, 1, 1};
    const char *file = NULL;
    int where = 0, dashdash = 0;
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!dashdash && a[0] == '-' && a[1]) {
            if (strcmp(a, "--") == 0) dashdash = 1;
            else if (strcmp(a, "--ansi") == 0) o.mode = 1;
            else if (strcmp(a, "--plain") == 0) o.mode = 0;
            else if (strcmp(a, "--final") == 0) o.final_only = 1;
            else if (strcmp(a, "--stats") == 0) o.stats = 1;
            else if (strcmp(a, "--wire2") == 0) o.wire = 2;
            else if (strcmp(a, "--wire1") == 0) o.wire = 1;
            else if (strcmp(a, "--where") == 0) where = 1;
            else if (strcmp(a, "--version") == 0) { printf("aura-pad %s\n", AURA_PAD_VERSION); return 0; }
            else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) { usage(); return 0; }
            else { usage(); return 2; }
        } else if (!file) {
            file = a;
        } else {
            fprintf(stderr, "aura-pad: one file at a time\n");
            pad_errlog_msg("aura-pad", "one file at a time");
            return 2;
        }
    }
    if (o.mode < 0)
        o.mode = isatty(STDOUT_FILENO) && getenv("NO_COLOR") == NULL;

    Launch L;
    memset(&L, 0, sizeof(L));
    /* Soft cannot see the tty (its stdout is a pipe). Pass the text area. */
    pad_term_cells(o.mode, &L.rows, &L.cols);
    if (!find_home(&L)) {
        fprintf(stderr,
                "aura-pad: cannot find the pad's Soft files (soft/pad/play.aura).\n"
                "  Reinstall (scripts/build_c.sh --install) or set AURA_PAD_HOME=<dir with soft/pad>.\n");
        pad_errlog_msg("aura-pad", "cannot find the pad Soft files");
        return 127;
    }
    if (file) resolve_file(file, L.file, sizeof(L.file));

    char cand[8][PATH_MAX];
    int nc = candidates(cand, 8);
    int found = 0;
    for (int i = 0; i < nc && !found; i++) {
        if (!is_exec(cand[i]))
            continue;
        fmt(L.soft, sizeof(L.soft), "%s", cand[i]);
        find_aura_path(&L);
        found = starts(L.soft, L.aura_path);
    }
    if (found) {
        /* L.soft / L.aura_path are set */
    } else if (find_docker(&L, cand, nc)) {
        L.docker_mode = 1;
        fmt(L.soft, sizeof(L.soft), "%s", BOX_AURA_SRC "/build/aura");
        if (!where)
            fprintf(stderr, "aura-pad: no aura runs natively here; starting Soft in docker (%s)\n",
                    getenv("AURA_PAD_IMAGE") && *getenv("AURA_PAD_IMAGE") ? getenv("AURA_PAD_IMAGE") : DOCKER_IMAGE);
    } else {
        fprintf(stderr,
                "aura-pad: cannot find Aura, the Soft runtime that runs the pad.\n"
                "  Build or install aura and put it on your PATH, or set AURA_BIN=/path/to/aura.\n"
                "  (With docker installed, aura-pad can also run an aura build inside docker.)\n");
        pad_errlog_msg("aura-pad", "cannot find Aura");
        return 127;
    }

    char st[24][2 * PATH_MAX + 64];
    char *cargv[64];
    build_argv(&L, cargv, 64, st);
    if (where) {
        printf("mode=%s\nsoft=%s\naura_path=%s\nhome=%s\nfile=%s\n", L.docker_mode ? "docker" : "native",
               L.soft, L.docker_mode ? BOX_AURA_SRC "/lib" : L.aura_path, L.home, L.file);
        printf("argv=");
        for (int i = 0; cargv[i]; i++) printf("%s%s", i ? " " : "", cargv[i]);
        printf("\n");
        return 0;
    }
    int to = -1, from = -1, errfd = -1;
    pid_t pid = spawn(&L, cargv, &to, &from, &errfd);
    if (pid < 0) {
        fprintf(stderr, "aura-pad: cannot start Soft (%s)\n", strerror(errno));
        pad_errlog_msg("aura-pad", "cannot start Soft");
        return 1;
    }
    return pad_play_loop(pid, to, from, errfd, &o);
}
