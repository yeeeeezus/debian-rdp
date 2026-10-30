#!/usr/bin/env python3
"""apk-install-helper.py — install an APK or XAPK onto the running emulator.

Usage:  python3 apk-install-helper.py <file.apk|file.xapk> [adb-path]

Used by front-proxy (/fapi/apk-install) and postboot-install.sh.
Prints a JSON result on stdout: {"ok": bool, "detail": "...", "package": "..."}

XAPK handling: unzip, install base + best-ABI split + density split via
adb install-multiple. On ABI mismatch (no ARM translation available) it
falls back to base + density only, which still works for apps whose base
APK carries no native libraries.
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import zipfile

ADB_DEFAULT = "/home/z/my-project/.android-cache/sdk/platform-tools/adb"
TIMEOUT = 900  # software emulation is slow; installs can take minutes


def run_adb(adb, *args, timeout=TIMEOUT):
    cmd = [adb] + list(args)
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "adb timed out after %ss" % timeout
    except Exception as e:
        return 125, str(e)


def package_of(path):
    """Best-effort package name from a file name (com.foo.bar.apk)."""
    b = os.path.basename(path)
    b = re.sub(r"\.(apk|xapk)$", "", b)
    return b if b.startswith("com.") or "." in b else b


def install_plain(adb, path):
    rc, out = run_adb(adb, "install", "-r", "-t", path)
    ok = rc == 0 and "Success" in out
    return {"ok": ok, "detail": out.strip().splitlines()[-1] if out.strip() else "",
            "package": package_of(path), "mode": "apk"}


def install_xapk(adb, path):
    tmp = tempfile.mkdtemp(prefix="xapk-", dir=os.path.dirname(path) or "/tmp")
    try:
        with zipfile.ZipFile(path) as z:
            z.extractall(tmp)
        apks = sorted(glob.glob(os.path.join(tmp, "*.apk")))
        if not apks:
            return {"ok": False, "detail": "no .apk files inside XAPK",
                    "package": package_of(path), "mode": "xapk"}
        base = [a for a in apks if not os.path.basename(a).startswith("config.")]
        abi = ([a for a in apks if "x86_64" in os.path.basename(a)] or
               [a for a in apks if "arm64_v8a" in os.path.basename(a)] or
               [a for a in apks if "x86" in os.path.basename(a)] or
               [a for a in apks if "armeabi" in os.path.basename(a)])
        dpi = [a for a in apks if re.search(r"config\.[0-9a-z]*dpi", os.path.basename(a))]
        langs = [a for a in apks if re.search(r"config\.(en|ar|de|es|fr|ru|tr|zh|ja|ko)\.apk",
                                              os.path.basename(a))]
        full = base + abi + dpi + langs
        rc, out = run_adb(adb, "install-multiple", "-r", "-t", *full)
        out2 = out
        if rc == 0 and "Success" in out:
            return {"ok": True, "detail": "installed (all splits)",
                    "package": package_of(base[0]) if base else package_of(path),
                    "mode": "xapk-full"}
        # fallback: base + density only (skip native-ABI split)
        minimal = base + dpi
        if len(minimal) < len(full):
            rc2, out2 = run_adb(adb, "install-multiple", "-r", "-t", *minimal)
            if rc2 == 0 and "Success" in out2:
                return {"ok": True, "detail": "installed (base+density, no ABI split)",
                        "package": package_of(base[0]) if base else package_of(path),
                        "mode": "xapk-minimal"}
        return {"ok": False, "detail": (out2 if len(minimal) < len(full) else out).strip()
                .splitlines()[-1] if (out or out2).strip() else "install failed",
                "package": package_of(path), "mode": "xapk"}
    finally:
        subprocess.run(["rm", "-rf", tmp], timeout=60)


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "detail": "usage: apk-install-helper.py <file> [adb]"}))
        sys.exit(2)
    path = sys.argv[1]
    adb = sys.argv[2] if len(sys.argv) > 2 else ADB_DEFAULT
    if not os.path.isfile(path):
        print(json.dumps({"ok": False, "detail": "file not found: %s" % path}))
        sys.exit(1)
    # make sure the adb server is up
    run_adb(adb, "start-server", timeout=30)
    res = None
    # The guest's system_server occasionally restarts under software
    # emulation (watchdog trips on slow I/O) — installs fail transiently
    # ("Can't find service", "Broken pipe", "device offline"). Just retry.
    for attempt in range(1, 4):
        res = install_xapk(adb, path) if path.lower().endswith(".xapk") \
            else install_plain(adb, path)
        if res["ok"]:
            break
        if attempt < 3:
            print(json.dumps({"ok": False, "retry": attempt,
                              "detail": "transient failure, retrying in 90s"}))
            sys.stdout.flush()
            import time
            time.sleep(90)
            continue
        break
    print(json.dumps(res))
    sys.exit(0 if res["ok"] else 1)


if __name__ == "__main__":
    main()
