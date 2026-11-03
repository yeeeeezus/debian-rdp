#!/usr/bin/env python3
"""Swap the Android emulator package with build 16696583 (37.3.6),
stream-extracting only the essential members (no Qt, no foreign-arch
qemu binaries) to survive this disk-tight sandbox."""
import io, os, struct, subprocess, sys, urllib.request, zipfile

URL = 'https://dl.google.com/android/repository/emulator-linux_x64-16696583.zip'
DEST = '/home/z/android-cache/sdk/emulator'

class HttpFile(io.RawIOBase):
    def __init__(s, url):
        s.url, s.pos = url, 0
        r = urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=30)
        s.len = int(r.headers['Content-Length']); r.close()
    def readable(s): return True
    def seekable(s): return True
    def read(s, n=-1):
        if n == -1: n = s.len - s.pos
        if n <= 0 or s.pos >= s.len: return b''
        end = min(s.pos+n, s.len)-1
        rq = urllib.request.Request(s.url, headers={'Range': f'bytes={s.pos}-{end}'})
        with urllib.request.urlopen(rq, timeout=300) as r:
            buf = b''
            while len(buf) < end-s.pos+1:
                c = r.read(end-s.pos+1-len(buf))
                if not c: break
                buf += c
        s.pos += len(buf); return buf
    def seek(s, o, w=0):
        s.pos = o if w == 0 else (s.pos+o if w == 1 else s.len+o); return s.pos
    def tell(s): return s.pos

hf = HttpFile(URL)
zf = zipfile.ZipFile(hf)

def wanted(n):
    if not n.startswith('emulator/') or n.endswith('/'):
        return False
    rel = n[9:]
    if '/qt/' in n or n.endswith(('.csv', '.txt')):
        return False
    if rel.startswith(('qemu/linux-x86_64/qemu-system-x86_64',)):
        return True
    if rel.startswith(('qemu/linux-x86_64/',)):
        return False          # foreign-arch / other qemu builds
    if rel.startswith(('qemu/',)):
        return True
    return '/' not in rel or rel.startswith(('lib/', 'lib64/', 'bin64/'))

members = [i for i in zf.infolist() if wanted(i.filename)]
total = sum(i.file_size for i in members)
print(f'{len(members)} members, {total/1e6:.0f} MB uncompressed', flush=True)

os.makedirs(DEST, exist_ok=True)
done = 0
for info in members:
    rel = info.filename[9:]
    if not rel:
        continue
    out = os.path.join(DEST, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    # raw byte range of this member
    hf.seek(info.header_offset)
    lh = hf.read(30)
    nl, el = struct.unpack('<HH', lh[26:30])
    data_off = info.header_offset + 30 + nl + el
    data_end = data_off + info.compress_size
    rc = subprocess.run(
        ['curl', '-s', '--retry', '3', '-r', f'{data_off}-{data_end}',
         '-o', out, URL]).returncode
    if rc != 0:
        print('CURL FAIL', info.filename, rc, flush=True); sys.exit(1)
    if info.compress_type != 0:   # deflated: decompress in place
        raw = open(out, 'rb').read()
        import zlib
        d = zlib.decompressobj(-15)
        data = d.decompress(raw) + d.flush()
        open(out, 'wb').write(data)
    os.chmod(out, 0o755 if info.filename.endswith(
        ('emulator', 'emulator-check', 'crashpad_handler', 'crashreport',
         'mksdcard', 'qemu-img', 'netsim', 'netsimd', 'nimble_bridge', 'qsn'))
        or '/bin64/' in info.filename or '/qemu/' in info.filename else 0o644)
    done += 1
    if done % 20 == 0:
        print(f'  {done}/{len(members)}', flush=True)
print(f'done: {done} files', flush=True)
