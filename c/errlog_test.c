/* Rotation check for c/errlog.c. Not installed. */
#define _POSIX_C_SOURCE 200809L

#include "errlog.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int fail(const char *m) {
    fprintf(stderr, "errlog_test: %s\n", m);
    return 1;
}

static long fsize(const char *p) {
    struct stat st;
    if (stat(p, &st) != 0)
        return -1;
    return (long)st.st_size;
}

static int contains(const char *path, const char *needle) {
    FILE *fp;
    char buf[8192];
    size_t n;
    fp = fopen(path, "r");
    if (!fp)
        return 0;
    n = fread(buf, 1, sizeof buf - 1, fp);
    fclose(fp);
    buf[n] = '\0';
    return strstr(buf, needle) != NULL;
}

static int line_ok(const char *path) {
    FILE *fp;
    char buf[512];
    int lines = 0;
    fp = fopen(path, "r");
    if (!fp)
        return 0;
    while (fgets(buf, sizeof buf, fp)) {
        size_t n = strlen(buf);
        if (n == 0 || buf[n - 1] != '\n') {
            fclose(fp);
            return 0;
        }
        if (!strstr(buf, " ERROR test: boom ")) {
            fclose(fp);
            return 0;
        }
        lines++;
    }
    fclose(fp);
    return lines > 0;
}

int main(void) {
    char dir[] = "/tmp/aura-pad-log-XXXXXX";
    char path[512], p1[520], p2[520];
    char msg[64];
    int i;
    long s0, s1, s2;
    const long cap = 120;
    if (!mkdtemp(dir))
        return fail("mkdtemp");
    if (snprintf(path, sizeof path, "%s/aura-pad.log", dir) >= (int)sizeof path)
        return fail("path");
    snprintf(p1, sizeof p1, "%s.1", path);
    snprintf(p2, sizeof p2, "%s.2", path);
    if (pad_errlog_open(path, (size_t)cap, 3) != 0)
        return fail("open");
    for (i = 0; i < 40; i++) {
        snprintf(msg, sizeof msg, "boom %02d something failed", i);
        pad_errlog_msg("test", msg);
    }
    pad_errlog_close();
    s0 = fsize(path);
    s1 = fsize(p1);
    s2 = fsize(p2);
    if (s0 < 0 || s1 < 0 || s2 < 0)
        return fail("missing rotated file");
    if (s0 > cap || s1 > cap || s2 > cap)
        return fail("a log grew past the cap");
    if (!contains(path, "boom 39"))
        return fail("newest line is not in the live log");
    if (contains(path, "boom 00") || contains(p1, "boom 00") || contains(p2, "boom 00"))
        return fail("the oldest line was kept");
    if (!line_ok(path) || !line_ok(p1) || !line_ok(p2))
        return fail("a log line was split or truncated");
    unlink(path);
    unlink(p1);
    unlink(p2);
    rmdir(dir);
    printf("ERRLOG_OK cap=%ld live=%ld\n", cap, s0);
    return 0;
}
