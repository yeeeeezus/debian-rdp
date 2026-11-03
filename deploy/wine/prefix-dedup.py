#!/usr/bin/env python3
"""Deduplicate a wine prefix's copied builtin DLLs: replace each identical
file in drive_c/windows/{system32,syswow64} with a RELATIVE symlink into the
wine lib tree (content-hash verified). Relative targets resolve both under
the HOST kernel (fakechroot execution) and inside a real chroot. Frees ~700
MB. Re-runnable: absolute links from an earlier run are converted in place.
"""
import hashlib, os, sys

S = "/home/z/debian/sysroot"
PREFIX = os.path.join(S, "home/debian/.wine/drive_c/windows")
WINE64 = "usr/lib/x86_64-linux-gnu/wine/x86_64-windows"
WINE32 = "usr/lib/x86_64-linux-gnu/wine/i386-windows"

def sha256(p, buf=1 << 20):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        while True:
            b = f.read(buf)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

freed = linked = kept = 0
for sub, wtree in (("system32", WINE64), ("syswow64", WINE32)):
    d = os.path.join(PREFIX, sub)
    if not os.path.isdir(d):
        continue
    wdir = os.path.join(S, wtree)
    for name in sorted(os.listdir(d)):
        f = os.path.join(d, name)
        w = os.path.join(wdir, name)
        relink = False
        if os.path.islink(f):
            tgt = os.readlink(f)
            if not tgt.startswith("/") and os.path.isfile(os.path.join(d, tgt)):
                continue            # already a valid relative link
            if tgt == f"/{wtree}/{name}":
                os.unlink(f)        # our old absolute link: convert to rel
                relink = True       # (hash-verified on the earlier run)
            else:
                continue            # unknown symlink, leave untouched
        elif not os.path.isfile(f):
            continue                # regular dir/device etc.
        if not os.path.isfile(w):
            kept += 1
            continue
        if not relink:
            try:
                if os.path.getsize(f) != os.path.getsize(w) or \
                   sha256(f) != sha256(w):
                    kept += 1
                    continue
            except OSError:
                kept += 1
                continue
        size = os.path.getsize(w)
        try:
            os.unlink(f)            # free the data blocks BEFORE linking
        except FileNotFoundError:
            pass
        os.symlink(os.path.relpath(w, d), f)
        if not relink:
            freed += size
        linked += 1

print(f"links total: {linked} ({freed / 1048576:.0f} MB deduped now), kept-as-copy: {kept}")
