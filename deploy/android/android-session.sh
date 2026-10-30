#!/bin/bash
# android-session.sh — around-boot orchestration for the emulator:
#   1. wait for qemu (then poll /proc, no forks — fork() fails under
#      extreme memory pressure)
#   2. the moment the package manager answers (MID-BOOT, while the host
#      still has ~1 GB headroom — this is critical, installs after the
#      memory floor drops trigger a guest watchdog restart spiral):
#        a. disable GMS (fresh AVDs only; persists in userdata)
#        b. install every cached APK (HelloTalk) unless already installed
#   3. wait for full boot completion (status reporting)
C=/home/z/my-project/.android-cache
ADB="$C/sdk/platform-tools/adb"
LOG="$C/avd/session.log"
exec >> "$LOG" 2>&1
echo "=== android-session start $(date)"

QPID=""
for i in $(seq 1 60); do
  QPID=$(pgrep -f qemu-system-x86_64 | head -1)
  [ -n "$QPID" ] && break
  sleep 2
done
[ -n "$QPID" ] || { echo "no emulator appeared"; exit 1; }
echo "qemu pid $QPID"
alive() { [ -d "/proc/$QPID" ]; }

pkg_of() { python3 - "$1" <<'PYEOF'
import json, re, sys, zipfile
f = sys.argv[1]
try:
    with zipfile.ZipFile(f) as z:
        print(json.loads(z.read("manifest.json").decode())["package_name"])
except Exception:
    print(re.sub(r"\.(apk|xapk)$", "", f.rsplit("/", 1)[-1]))
PYEOF
}

pm_up=""
for i in $(seq 1 400); do
  st=$(timeout 8 "$ADB" get-state 2>/dev/null | tr -d '\r')
  if [ "$st" = "device" ]; then
    p=$(timeout 12 "$ADB" shell pm path com.google.android.gms 2>/dev/null | tr -d '\r')
    b=$(timeout 12 "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    if [[ "$p" == *"package:"* ]] || [ "$b" = "1" ]; then
      pm_up=1
      if [[ "$p" == *"package:"* ]] && [ ! -f "$C/avd/.gms-disabled" ]; then
        echo "pm alive $(date) — disabling GMS before it churns"
        for pkg in com.google.android.gms com.google.android.gsf; do
          timeout 40 "$ADB" shell pm disable-user --user 0 "$pkg" 2>&1 | tail -1
        done
        touch "$C/avd/.gms-disabled"
        echo "gms disabled $(date)"
      fi
      break
    fi
  fi
  alive || { echo "emulator gone"; exit 1; }
  sleep 3
done

if [ -n "$pm_up" ]; then
  echo "installing cached APKs early ($(date))"
  for f in "$C"/apks/*.apk "$C"/apks/*.xapk; do
    [ -f "$f" ] || continue
    pkg=$(pkg_of "$f")
    have=$(timeout 15 "$ADB" shell pm path "$pkg" 2>/dev/null | tr -d '\r')
    if [[ "$have" == *"package:"* ]]; then
      echo "--- $pkg already installed, skipping"
      continue
    fi
    echo "--- installing $(basename "$f") as $pkg"
    timeout 960 python3 "$C/apk-install-helper.py" "$f"
    echo "    rc=$?"
  done
  touch "$C/avd/.apks-installed"
fi

for j in $(seq 1 160); do
  b=$(timeout 12 "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [ "$b" = "1" ] && { echo "boot completed $(date)"; exit 0; }
  alive || { echo "emulator gone (post-install)"; exit 1; }
  sleep 5
done
echo "session: boot wait timed out"
