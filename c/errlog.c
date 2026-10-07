#define _POSIX_C_SOURCE 200809L

#include "errlog.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

static char g_path[PATH_MAX];
static size_t g_max = 262144;
static int g_keep = 3;
static int g_ready = 0;
static int g_said = 0;
static FILE *g_fp = NULL;
static size_t g_size = 0;

static int default_path(char *out, size_t n) {
    const char *xdg = getenv("XDG_STATE_HOME");
    const char *home = getenv("HOME");
    int k;
    if (xdg && *xdg)
        k = snprintf(out, n, "%s/aura-pad/aura-pad.log", xdg);
    else if (home && *home)
        k = snprintf(out, n, "%s/.local/state/aura-pad/aura-pad.log", home);
    else
        k = snprintf(out, n, "/tmp/aura-pad-%ld.log", (long)getuid());
    return k > 0 && (size_t)k + 3 < n;
}

static int mkdir_parent(const char *path) {
    char tmp[PATH_MAX];
    size_t n = strlen(path);
    char *p;
    if (n == 0 || n >= sizeof(tmp))
        return -1;
    memcpy(tmp, path, n + 1);
    p = strrchr(tmp, '/');
    if (!p || p == tmp)
        return 0;
    *p = '\0';
    for (p = tmp + 1; *p; p++) {
        if (*p != '/')
            continue;
        *p = '\0';
        if (mkdir(tmp, 0700) != 0 && errno != EEXIST)
            return -1;
        *p = '/';
    }
    if (mkdir(tmp, 0700) != 0 && errno != EEXIST)
        return -1;
    return 0;
}

static void rotate_now(void) {
    char a[PATH_MAX], b[PATH_MAX];
    int n = g_keep - 1;
    int i;
    if (g_fp) {
        fclose(g_fp);
        g_fp = NULL;
    }
    if (n < 1)
        n = 1;
    if (n > 7)
        n = 7;
    if (snprintf(a, sizeof a, "%s.%d", g_path, n) < (int)sizeof a)
        unlink(a);
    for (i = n; i >= 2; i--) {
        int ka = snprintf(a, sizeof a, "%s.%d", g_path, i - 1);
        int kb = snprintf(b, sizeof b, "%s.%d", g_path, i);
        if (ka > 0 && kb > 0 && ka < (int)sizeof a && kb < (int)sizeof b)
            rename(a, b);
    }
    if (snprintf(b, sizeof b, "%s.1", g_path) < (int)sizeof b)
        rename(g_path, b);
    g_size = 0;
}

static size_t cap_of(size_t max_bytes) {
    const char *e;
    char *end = NULL;
    unsigned long v;
    if (max_bytes != 0)
        return max_bytes;
    e = getenv("AURA_PAD_LOG_MAX");
    if (e && *e) {
        v = strtoul(e, &end, 10);
        if (end != e && *end == '\0' && v >= 64UL && v < 1000000000UL)
            return (size_t)v;
    }
    return 262144;
}

int pad_errlog_open(const char *path, size_t max_bytes, int keep) {
    char chosen[PATH_MAX];
    if (path && *path) {
        if (strlen(path) + 3 >= sizeof chosen)
            return -1;
        memcpy(chosen, path, strlen(path) + 1);
    } else if (!default_path(chosen, sizeof chosen)) {
        return -1;
    }
    memcpy(g_path, chosen, strlen(chosen) + 1);
    g_max = cap_of(max_bytes);
    g_keep = keep > 0 ? keep : 3;
    g_ready = 1;
    if (g_fp) {
        fclose(g_fp);
        g_fp = NULL;
    }
    g_size = 0;
    return 0;
}

static int ensure_open(void) {
    struct stat st;
    if (g_fp)
        return 0;
    if (!g_ready && pad_errlog_open(NULL, 0, 0) != 0)
        return -1;
    if (g_path[0] == '\0' || mkdir_parent(g_path) != 0)
        return -1;
    if (stat(g_path, &st) == 0 && st.st_size >= 0 && (size_t)st.st_size >= g_max)
        rotate_now();
    g_fp = fopen(g_path, "a");
    if (!g_fp)
        return -1;
    if (stat(g_path, &st) == 0 && st.st_size >= 0)
        g_size = (size_t)st.st_size;
    else
        g_size = 0;
    return 0;
}

void pad_errlog_msg(const char *where, const char *msg) {
    char when[32];
    time_t t;
    struct tm tm;
    size_t add;
    int n;
    if (!where)
        where = "aura-pad";
    if (!msg)
        msg = "";
    if (ensure_open() != 0)
        return;
    t = time(NULL);
    if (!localtime_r(&t, &tm) || strftime(when, sizeof when, "%Y-%m-%d %H:%M:%S", &tm) == 0)
        memcpy(when, "0000-00-00 00:00:00", 20);
    /* date + " ERROR " + where + ": " + msg + newline, roughly */
    add = strlen(when) + strlen(where) + strlen(msg) + 16;
    if (g_size > 0 && g_size + add >= g_max) {
        rotate_now();
        if (ensure_open() != 0)
            return;
    }
    n = fprintf(g_fp, "%s ERROR %s: %s\n", when, where, msg);
    if (n > 0)
        g_size += (size_t)n;
    fflush(g_fp);
    if (!g_said) {
        g_said = 1;
        fprintf(stderr, "aura-pad: error log: %s\n", g_path);
    }
}

void pad_errlog_close(void) {
    if (g_fp) {
        fclose(g_fp);
        g_fp = NULL;
    }
}
