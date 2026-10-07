/* Rotating error log for aura-pad. The viewport still does not decide
 * what a key means; this only records failures so they can be found
 * later. Lines are appended to one file. When the file reaches the
 * size cap it is renamed aside and a new file is started. */
#ifndef PAD_ERRLOG_H
#define PAD_ERRLOG_H

#include <stddef.h>

/* Remember where to log. path NULL uses $AURA_PAD_LOG, else
 * $XDG_STATE_HOME/aura-pad/aura-pad.log, else
 * $HOME/.local/state/aura-pad/aura-pad.log, else /tmp/aura-pad-<uid>.log.
 * max_bytes 0 uses $AURA_PAD_LOG_MAX when that is a number >= 64, else
 * 262144. keep 0 means 3 files (the live one plus two older). The file
 * is created on the first message, not here. Returns 0, or -1 if the
 * path does not fit. */
int pad_errlog_open(const char *path, size_t max_bytes, int keep);

/* One error line: "<time> ERROR <where>: <msg>". No-op if the file
 * cannot be opened. The first successful line also names the path on
 * stderr. A message longer than the cap is written whole; the next
 * message starts a new file. */
void pad_errlog_msg(const char *where, const char *msg);

void pad_errlog_close(void);

#endif
