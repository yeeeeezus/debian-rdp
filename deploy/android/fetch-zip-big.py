#!/usr/bin/env python3
"""Stream a huge member out of a remote zip with minimal RAM:
1) ranged-read the central directory to locate the member + its method
2) curl the member's raw byte range from the zip URL
3) if stored  -> write through; if deflated -> streaming-decompress
Usage: fetch-zip-big.py <zip-url> <member-suffix> <outfile>"""
import io, subprocess, sys, urllib.request, zipfile

url, member_suffix, out = sys.argv[1], sys.argv[2], sys.argv[3]

class HttpFile(io.RawIOBase):
    def __init__(self, url):
        self.url, self.pos = url, 0
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
        else: self.pos = self.len + off
        return self.pos
    def tell(self): return self.pos

hf = HttpFile(url)
zf = zipfile.ZipFile(hf)
info = next(i for i in zf.infolist() if i.filename.endswith(member_suffix))
print(f"member={info.filename} size={info.file_size} csize={info.compress_size} "
      f"method={'stored' if info.compress_type == 0 else 'deflate'}", flush=True)

# local file header: 30 bytes + name + extra (extra in central != local!)
hdr_off = info.header_offset
hf.seek(hdr_off)
lh = hf.read(30)
import struct
name_len, extra_len = struct.unpack('<HH', lh[26:30])
data_off = hdr_off + 30 + name_len + extra_len
data_end = data_off + info.compress_size
print(f"raw byte range: {data_off}-{data_end}", flush=True)

if info.compress_type == 0:   # stored: raw bytes ARE the file
    cmd = ['curl', '-s', '--retry', '3', '-r', f'{data_off}-{data_end}',
           '-o', out, url]
    rc = subprocess.run(cmd).returncode
    print('curl rc', rc, flush=True)
    sys.exit(rc)
else:                          # deflated: stream-decompress
    p1 = subprocess.Popen(
        ['curl', '-s', '--retry', '3', '-r', f'{data_off}-{data_end}', url],
        stdout=subprocess.PIPE)
    import zlib
    d = zlib.decompressobj(-15)
    written = 0
    with open(out, 'wb') as f:
        while True:
            chunk = p1.stdout.read(1024 * 1024)
            if not chunk: break
            f.write(d.decompress(chunk))
            written = f.tell()
            if written % (256 * 1024 * 1024) < 1024 * 1024:
                print(f'  {written/1e9:.2f} GB...', flush=True)
        f.write(d.flush())
    p1.wait()
    print(f'done: {written/1e9:.3f} GB written', flush=True)
