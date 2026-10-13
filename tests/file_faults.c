/* macOS interposition for file-faults.sh. Inject one failure into the selected operation. */
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int injected;
static int target_fd = -1;
static int fault(const char *name) {
    const char *selected = getenv("RAFTAAR_TEST_FAULT");
    if (injected || !selected || strcmp(name, selected)) return 0;
    injected = 1;
    const char *error = getenv("RAFTAAR_TEST_ERRNO");
    errno = error ? atoi(error) : EIO;
    return 1;
}

#define INTERPOSE(name) \
    __attribute__((used, section("__DATA,__interpose"))) \
    static const struct { const void *replacement, *original; } entry_##name = \
        { (const void *)test_##name, (const void *)name }

static int test_open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = va_arg(args, int);
        va_end(args);
    }
    int fd = open(path, flags, mode);
    const char *target = getenv("RAFTAAR_TEST_PATH");
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    if (fd >= 0 && ((target && !strcmp(path, target)) || !strncmp(base, ".raftaar-", 6))) target_fd = fd;
    return fd;
}
INTERPOSE(open);

static ssize_t test_write(int fd, const void *buf, size_t len) {
    const char *delay = getenv("RAFTAAR_TEST_AGENT_DELAY_MS");
    if (fd == STDOUT_FILENO && len >= 8 && delay && !memcmp(buf, "RAHPAGE3", 8)) {
        const char *ready = getenv("RAFTAAR_TEST_AGENT_READY");
        if (ready) {
            FILE *marker = fopen(ready, "w");
            if (marker) { fputs("ready\n", marker); fclose(marker); }
        }
        usleep((useconds_t)atoi(delay) * 1000);
    }
    if (fd == target_fd && fault("write")) return -1;
    if (fd == target_fd && fault("short-write") && len > 2) len = 2;
    return write(fd, buf, len);
}
INTERPOSE(write);

static ssize_t test_read(int fd, void *buf, size_t len) {
    if (fd == target_fd && fault("read")) return -1;
    if (fd == target_fd && fault("short-read") && len > 7) len = 7;
    return read(fd, buf, len);
}
INTERPOSE(read);

static int test_fsync(int fd) {
    if (fd == target_fd && fault("fsync")) return -1;
    return fsync(fd);
}
INTERPOSE(fsync);

static int test_close(int fd) {
    int result = close(fd);
    if (fd == target_fd && fault("close")) return -1;
    return result;
}
INTERPOSE(close);

static int test_fchmod(int fd, mode_t mode) {
    if (fd == target_fd && fault("fchmod")) return -1;
    return fchmod(fd, mode);
}
INTERPOSE(fchmod);

static int test_fstat(int fd, struct stat *st) {
    if (fd == target_fd && fault("fstat")) return -1;
    return fstat(fd, st);
}
INTERPOSE(fstat);

static int test_rename(const char *from, const char *to) {
    if (fault("rename")) return -1;
    return rename(from, to);
}
INTERPOSE(rename);
