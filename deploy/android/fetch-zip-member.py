#!/usr/bin/env python3
"""Stream-extract a single file from a remote zip via HTTP Range requests.
Used to fetch qemu-system-x86_64-headless from the Android emulator
package without storing the 350 MB zip on this disk-tight sandbox."""
import sys, urllib.request, zipfile, io

url, member, out = sys.argv[1], sys.argv[2], sys.argv[3]

class HttpFile(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        self.pos = 0
        req = urllib.request.Request(url, method='HEAD')
        with urllib.request.urlopen(req, timeout=60) as r:
            self.len = int(r.headers['Content-Length'])

    def readable(self): return True
    def seekable(self): return True

    def read(self, n=-1):
        if n == -1: n = self.len - self.pos
        if n <= 0 or self.pos >= self.len: return b''
        end = min(self.pos + n, self.len) - 1
        req = urllib.request.Request(
            self.url, headers={'Range': f'bytes={self.pos}-{end}'})
        with urllib.request.urlopen(req, timeout=300) as r:
            buf = b''
            while len(buf) < end - self.pos + 1:
                chunk = r.read(end - self.pos + 1 - len(buf))
                if not chunk: break
                buf += chunk
        self.pos += len(buf)
        return buf

    def seek(self, off, whence=0):
        if whence == 0: self.pos = off
        elif whence == 1: self.pos += off
        elif whence == 2: self.pos = self.len + off
        return self.pos

    def tell(self): return self.pos

hf = HttpFile(url)
with zipfile.ZipFile(hf) as z:
    names = [n for n in z.namelist() if n.endswith(member)]
    if not names:
        sys.exit('member not found; candidates: ' +
                 ', '.join(n for n in z.namelist() if 'headless' in n))
    data = z.read(names[0])
    with open(out, 'wb') as f:
        f.write(data)
    print(f'extracted {names[0]} -> {out} ({len(data)} bytes)')
