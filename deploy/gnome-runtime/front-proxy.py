#!/usr/bin/env python3
"""front-proxy.py — smart ingress for the Debian remote desktop on :3000.

The platform edge proxy (:81) can only reach ONE port (:3000), which
websockify traditionally owned. This process takes over :3000 and:

  * serves /fapi/*  — the file bridge between the browser and the
                      desktop home directories (upload / list / download)
  * transparently proxies EVERYTHING ELSE (static noVNC files + the
                      /websockify websocket tunnel) to websockify on
                      127.0.0.1:3001 at the byte level, which makes
                      websockets work without any protocol re-encoding.

Runs on the HOST python (no chroot, no fakechroot), managed by
debian-supervisor. If it crash-loops, the supervisor falls back to plain
websockify on :3000 so the desktop is never unreachable (file bridge
offline in that mode, VNC keeps working).

stdlib only. Log lines go to stdout (supervisor redirects to
run/front-proxy.log).
"""
import asyncio
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse

LISTEN_HOST = '0.0.0.0'
LISTEN_PORT = 3000
BACKEND_HOST = '127.0.0.1'
BACKEND_PORT = 3001

HOME = '/home/z/debian/sysroot/home/debian'
SHARE_DIRS = ('Downloads', 'Desktop', 'Documents', 'Pictures', 'Music', 'Videos')
UPLOAD_DIR = 'Downloads'
MAX_BODY = 2 * 1024 ** 3          # 2 GB per upload
MIN_DISK_FREE = 400 * 1024 ** 2   # abort upload if less than this free
HEAD_LIMIT = 64 * 1024            # max request head size
NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9 ._()+,\-]{0,199}\Z")
CHUNK = 256 * 1024

# Android runtime (userspace emulator under .android-cache, survives resets)
ACACHE = '/home/z/my-project/.android-cache'
ADB = ACACHE + '/sdk/platform-tools/adb'
EMU_LAUNCH = ACACHE + '/emulator-launch.sh'
POSTBOOT = ACACHE + '/android-session.sh'
APK_HELPER = ACACHE + '/apk-install-helper.py'

started = time.strftime('%F %T')


# ----------------------------------------------------------------- helpers
def log(msg):
    print('%s %s' % (time.strftime('%F %T'), msg), flush=True)


def safe_dir(d):
    return d if d in SHARE_DIRS else None


def safe_name(n):
    if not n or '/' in n or '\\' in n or n.startswith('.') or '..' in n:
        return None
    return n if NAME_RE.match(n) else None


async def send(client, status, reason, body=b'', ctype='text/plain; charset=utf-8',
               extra=()):
    if isinstance(body, str):
        body = body.encode()
    head = 'HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n' \
           'Cache-Control: no-store\r\nConnection: close\r\n' % (
               status, reason, ctype, len(body))
    for h in extra:
        head += h + '\r\n'
    head += '\r\n'
    client.write(head.encode('latin1'))
    if body:
        client.write(body)
    await client.drain()
    client.close()


async def send_json(client, obj, status=200):
    await send(client, status, 'OK' if status == 200 else 'ERR',
               json.dumps(obj), 'application/json')


# ---------------------------------------------------------------- file API
async def api_list(client, q):
    d = safe_dir(q.get('dir', [UPLOAD_DIR])[0])
    if not d:
        return await send_json(client, {'error': 'bad dir'}, 400)
    root = os.path.join(HOME, d)
    try:
        entries = []
        with os.scandir(root) as it:
            for e in it:
                try:
                    if e.name.startswith('.') or e.name.endswith('.part'):
                        continue
                    st = e.stat()
                    if not e.is_file():
                        continue
                    entries.append({'name': e.name, 'size': st.st_size,
                                    'mtime': int(st.st_mtime)})
                except OSError:
                    continue
        entries.sort(key=lambda x: -x['mtime'])
        return await send_json(client, {'dir': d, 'files': entries})
    except FileNotFoundError:
        os.makedirs(root, exist_ok=True)
        return await send_json(client, {'dir': d, 'files': []})
    except OSError as e:
        return await send_json(client, {'error': str(e)}, 500)


async def api_upload(client, q, headers):
    name = safe_name(q.get('name', [''])[0])
    if not name:
        return await send_json(client, {'error': 'bad name'}, 400)
    try:
        length = int(headers.get('content-length', '0'))
    except ValueError:
        return await send_json(client, {'error': 'bad length'}, 400)
    if length < 0 or length > MAX_BODY:
        return await send_json(client, {'error': 'file too large (max 2 GB)'}, 413)
    if shutil.disk_usage(HOME).free - length < MIN_DISK_FREE:
        return await send_json(client, {'error': 'not enough disk space'}, 507)

    dest = os.path.join(HOME, UPLOAD_DIR, name)
    tmp = dest + '.part'
    received = 0
    try:
        with open(tmp, 'wb') as f:
            while received < length:
                chunk = await client.read(min(CHUNK, length - received))
                if not chunk:
                    break
                f.write(chunk)
                received += len(chunk)
        if received != length:
            os.unlink(tmp)
            return await send_json(client, {'error': 'truncated upload'}, 400)
        os.rename(tmp, dest)
        os.chmod(dest, 0o644)
    except OSError as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return await send_json(client, {'error': str(e)}, 500)
    log('upload %s (%d bytes) -> %s' % (name, received, UPLOAD_DIR))
    return await send_json(client, {'ok': True, 'name': name, 'size': received,
                                    'dir': UPLOAD_DIR})


async def api_download(client, q):
    d = safe_dir(q.get('dir', [UPLOAD_DIR])[0])
    name = safe_name(q.get('name', [''])[0])
    if not d or not name:
        return await send_json(client, {'error': 'bad request'}, 400)
    root = os.path.realpath(os.path.join(HOME, d))
    fpath = os.path.realpath(os.path.join(root, name))
    if not fpath.startswith(root + os.sep):
        return await send_json(client, {'error': 'forbidden'}, 403)
    if not os.path.isfile(fpath):
        return await send_json(client, {'error': 'not found'}, 404)

    size = os.path.getsize(fpath)
    quoted = urllib.parse.quote(name)
    head = ('HTTP/1.1 200 OK\r\n'
            'Content-Type: application/octet-stream\r\n'
            'Content-Length: %d\r\n'
            'Content-Disposition: attachment; filename="%s"; '
            'filename*=UTF-8\'\'%s\r\n'
            'Cache-Control: no-store\r\n'
            'Connection: close\r\n\r\n') % (size, name.replace('"', ''), quoted)
    client.write(head.encode('latin1'))
    sent = 0
    with open(fpath, 'rb') as f:
        while True:
            chunk = f.read(CHUNK)
            if not chunk:
                break
            client.write(chunk)
            sent += len(chunk)
            await client.drain()
    client.close()
    log('download %s from %s (%d bytes)' % (name, d, sent))


# -------------------------------------------------------------- android fapi
def android_pid():
    try:
        pid = int(open(ACACHE + '/avd/emulator.pid').read().strip())
        os.kill(pid, 0)
        return pid
    except Exception:
        return None


async def adb_query(args, timeout=12):
    try:
        p = await asyncio.create_subprocess_exec(
            ADB, *args,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
        out = await asyncio.wait_for(p.communicate(), timeout)
        return out[0].decode('utf-8', 'replace')
    except Exception:
        return ''


async def android_state():
    pid = android_pid()
    running = pid is not None
    adb_state = boot = None
    installed = None
    if running:
        out = await adb_query(['devices'])
        for line in out.splitlines():
            if line.startswith('emulator-') and len(line.split()) > 1:
                adb_state = line.split()[1]
        if adb_state == 'device':
            boot = (await adb_query(
                ['shell', 'getprop', 'sys.boot_completed'], 15)).strip()
            if boot == '1':
                pk = await adb_query(
                    ['shell', 'pm', 'list', 'packages', 'com.hellotalk'], 15)
                installed = 'package:com.hellotalk' in pk
    provisioned = (os.path.isdir(ACACHE + '/sdk/system-images')
                   and os.access(ADB, os.X_OK))
    return {'provisioned': provisioned, 'running': running, 'pid': pid,
            'adb': adb_state, 'boot_completed': boot == '1',
            'hellotalk_installed': installed, 'avd': 'android30'}


async def api_android(client, q):
    return await send_json(client, await android_state())


async def api_android_start(client, q):
    if android_pid() is not None:
        return await send_json(client, {'ok': True, 'already_running': True})
    if not os.access(EMU_LAUNCH, os.X_OK):
        return await send_json(client,
                               {'ok': False, 'error': 'android not provisioned'}, 500)
    # launch the emulator, then the around-boot session, fully detached
    # so they survive proxy restarts (own sessions, not our children)
    for script in (EMU_LAUNCH, POSTBOOT):
        if os.access(script, os.X_OK):
            subprocess.Popen(['setsid', 'bash', script],
                             stdout=open(ACACHE + '/avd/api-start.log', 'a'),
                             stderr=subprocess.STDOUT,
                             stdin=subprocess.DEVNULL,
                             start_new_session=True)
            log('android start requested -> %s' % script)
    return await send_json(client, {'ok': True, 'started': True})


async def api_android_view(client, q):
    """Open a scrcpy window (scaled view of the emulator) on the desktop."""
    SCRCRY = ACACHE + '/scrcpy/run.sh'
    if android_pid() is None:
        return await send_json(client, {'ok': False, 'error': 'emulator not running'}, 409)
    if not os.access(SCRCRY, os.X_OK):
        return await send_json(client, {'ok': False, 'error': 'scrcpy missing'}, 500)
    if subprocess.run(['pgrep', '-f', 'scrcpy.*--window-title Android'],
                      capture_output=True).returncode == 0:
        return await send_json(client, {'ok': True, 'already_open': True})
    subprocess.Popen(['setsid', 'bash', SCRCRY],
                     stdout=open(ACACHE + '/avd/scrcpy.log', 'a'),
                     stderr=subprocess.STDOUT,
                     stdin=subprocess.DEVNULL,
                     env={**os.environ, 'DISPLAY': ':1'},
                     start_new_session=True)
    log('android view requested (scrcpy)')
    return await send_json(client, {'ok': True, 'opened': True})


async def api_apk_install(client, q, method):
    if method != 'POST':
        return await send_json(client, {'ok': False, 'error': 'POST required'}, 405)
    src = (q.get('src') or [''])[0]
    d, _, name = src.partition('/')
    if safe_dir(d) is None or safe_name(name) is None:
        return await send_json(client, {'ok': False, 'error': 'bad src'}, 400)
    full = os.path.join(HOME, d, name)
    if not os.path.isfile(full):
        return await send_json(client, {'ok': False, 'error': 'no such file'}, 404)
    if android_pid() is None:
        return await send_json(client, {'ok': False, 'error': 'emulator not running'}, 409)
    if not os.path.isfile(APK_HELPER):
        return await send_json(client, {'ok': False, 'error': 'helper missing'}, 500)
    loop = asyncio.get_event_loop()

    def _run():
        return subprocess.run([sys.executable, APK_HELPER, full],
                              capture_output=True, text=True, timeout=960)
    try:
        p = await loop.run_in_executor(None, _run)
        lines = (p.stdout or '').strip().splitlines()
        res = json.loads(lines[-1]) if lines else {'ok': False, 'detail': 'no output'}
        log('apk-install %s -> ok=%s (%s)' % (name, res.get('ok'), res.get('mode')))
        return await send_json(client, res)
    except Exception as e:
        return await send_json(client, {'ok': False, 'error': str(e)}, 500)


async def handle_api(client, method, path):
    u = urllib.parse.urlparse(path)
    q = urllib.parse.parse_qs(u.query)

    # read the request head (again, for headers) - the caller already
    # consumed it, headers are passed via a queue from the reader loop
    if u.path == '/fapi/health':
        return await send(client, 200, 'OK',
                          'ok (front-proxy up since %s)' % started)
    if u.path == '/fapi/dirs':
        return await send_json(client, {'dirs': list(SHARE_DIRS)})
    if u.path == '/fapi/list' and method == 'GET':
        return await api_list(client, q)
    if u.path == '/fapi/android' and method == 'GET':
        return await api_android(client, q)
    if u.path == '/fapi/android/start' and method == 'POST':
        return await api_android_start(client, q)
    if u.path == '/fapi/android/view' and method == 'POST':
        return await api_android_view(client, q)
    if u.path == '/fapi/apk-install' and method == 'POST':
        return await api_apk_install(client, q, method)
    if u.path == '/fapi/download' and method == 'GET':
        return await api_download(client, q)
    return await send_json(client, {'error': 'unknown endpoint'}, 404)


# ------------------------------------------------------------ proxy plumbing
async def pipe(reader, writer):
    try:
        while True:
            data = await reader.read(CHUNK)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.TimeoutError, OSError):
        pass
    finally:
        try:
            writer.close()
        except OSError:
            pass


async def handle(client, client_w):
    # asyncio.start_server calls back with (reader, writer) as two args.
    # 'client' is the StreamReader; wrap the writer so the rest of the
    # code can treat the pair as one object.
    class _W:
        def __init__(self, r, w):
            self.r, self.w = r, w
        def write(self, d):
            self.w.write(d)
        async def drain(self):
            await self.w.drain()
        def close(self):
            self.w.close()
        async def read(self, n=-1):
            return await self.r.read(n)
        async def readuntil(self, sep=b'\r\n\r\n'):
            return await self.r.readuntil(sep)
    c = _W(client, client_w)
    try:
        head = await asyncio.wait_for(c.readuntil(b'\r\n\r\n'),
                                      timeout=90)
    except (asyncio.IncompleteReadError, asyncio.TimeoutError,
            asyncio.LimitOverrunError, ConnectionError):
        c.close()
        return

    first = head.split(b'\r\n', 1)[0].decode('latin1', 'replace')
    parts = first.split()
    if len(parts) < 3:
        c.close()
        return
    method, path = parts[0].upper(), parts[1]

    # ---- local file-bridge endpoints ----
    if path.startswith('/fapi/'):
        # parse headers from the head we already have
        headers = {}
        for line in head.split(b'\r\n\r\n', 1)[0].split(b'\r\n')[1:]:
            if b':' in line:
                k, v = line.split(b':', 1)
                headers[k.decode('latin1').strip().lower()] = \
                    v.decode('latin1').strip()
        if path.split('?')[0] == '/fapi/upload' and method == 'POST':
            u = urllib.parse.urlparse(path)
            q = urllib.parse.parse_qs(u.query)
            return await api_upload(c, q, headers)
        return await handle_api(c, method, path)

    # ---- everything else: transparent byte-level proxy to websockify ----
    try:
        backend_reader, backend_writer = await asyncio.wait_for(
            asyncio.open_connection(BACKEND_HOST, BACKEND_PORT), timeout=10)
    except (ConnectionError, asyncio.TimeoutError, OSError):
        await send(c, 502, 'Bad Gateway',
                   'desktop backend not running yet - retrying in a moment')
        return
    backend_writer.write(head)
    await backend_writer.drain()
    await asyncio.gather(pipe(c.r, backend_writer),
                         pipe(backend_reader, c.w))


async def main():
    server = await asyncio.start_server(handle, LISTEN_HOST, LISTEN_PORT,
                                        limit=HEAD_LIMIT)
    log('front-proxy up on :%d -> backend %s:%d (file bridge + ws passthrough)'
        % (LISTEN_PORT, BACKEND_HOST, BACKEND_PORT))
    async with server:
        await server.serve_forever()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
