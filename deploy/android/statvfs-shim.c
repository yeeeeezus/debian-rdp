#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <sys/statvfs.h>
#include <sys/statfs.h>

/* Report >= 64 GiB free so the Android emulator's 2 GiB pre-flight
   disk-space check always passes on this space-constrained sandbox.
   Only affects processes that preload this .so (the emulator tree). */

static const unsigned long long FAKE_BYTES = 64ULL << 30;

static void bump_vfs(unsigned long long *bavail, unsigned long long *bfree,
                     unsigned long long bsize) {
    if (!bsize) bsize = 4096;
    unsigned long long want = FAKE_BYTES / bsize;
    if (*bavail < want) *bavail = want;
    if (*bfree < *bavail) *bfree = *bavail;
}

int statvfs(const char *path, struct statvfs *st) {
    static int (*real_fn)(const char *, struct statvfs *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "statvfs");
    int r = real_fn(path, st);
    if (r == 0 && st)
        bump_vfs((unsigned long long *)&st->f_bavail,
                 (unsigned long long *)&st->f_bfree,
                 (unsigned long long)st->f_bsize);
    return r;
}

int statvfs64(const char *path, struct statvfs64 *st) {
    static int (*real_fn)(const char *, struct statvfs64 *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "statvfs64");
    int r = real_fn(path, st);
    if (r == 0 && st)
        bump_vfs((unsigned long long *)&st->f_bavail,
                 (unsigned long long *)&st->f_bfree,
                 (unsigned long long)st->f_bsize);
    return r;
}

int statfs(const char *path, struct statfs *st) {
    static int (*real_fn)(const char *, struct statfs *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "statfs");
    int r = real_fn(path, st);
    if (r == 0 && st)
        bump_vfs((unsigned long long *)&st->f_bavail,
                 (unsigned long long *)&st->f_bfree,
                 (unsigned long long)st->f_bsize);
    return r;
}

int statfs64(const char *path, struct statfs64 *st) {
    static int (*real_fn)(const char *, struct statfs64 *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "statfs64");
    int r = real_fn(path, st);
    if (r == 0 && st)
        bump_vfs((unsigned long long *)&st->f_bavail,
                 (unsigned long long *)&st->f_bfree,
                 (unsigned long long)st->f_bsize);
    return r;
}
