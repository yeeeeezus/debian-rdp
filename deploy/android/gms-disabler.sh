#!/bin/bash
# gms-disabler.sh — disable the Google-Play-Services churn that OOMs the
# 4 GB host. Strikes as soon as the package manager answers (mid-boot,
# BEFORE GMS receives BOOT_COMPLETED). Persists in AVD userdata, so this
# is only a race on the very first boot after (re)creation.
# Uses /proc/<pid> existence tests (no forks) — fork() can transiently
# fail under extreme memory pressure and must not abort the race.
C=/home/z/my-project/.android-cache
ADB="$C/sdk/platform-tools/adb"
LOG="$C/avd/gms-disabler.log"
exec >> "$LOG" 2>&1
echo "=== gms-disabler start $(date)"
[ -f "$C/avd/.gms-disabled" ] && { echo "already disabled (flag)"; exit 0; }

# 1. remember the qemu pid (launcher needs a few seconds to spawn it)
QPID=""
for i in $(seq 1 60); do
  QPID=$(pgrep -f qemu-system-x86_64 | head -1)
  [ -n "$QPID" ] && break
  sleep 2
done
[ -n "$QPID" ] || { echo "no emulator appeared; exiting"; exit 1; }
echo "qemu pid $QPID"
alive() { [ -d "/proc/$QPID" ]; }

# 2. wait for adbd + package manager
for i in $(seq 1 400); do
  st=$(timeout 8 "$ADB" get-state 2>/dev/null | tr -d '\r')
  if [ "$st" = "device" ]; then
    p=$(timeout 12 "$ADB" shell pm path com.google.android.gms 2>/dev/null | tr -d '\r')
    if [ -n "$p" ] && [[ "$p" == *"package:"* ]]; then
      echo "package manager alive ($(date)) — disabling GMS NOW"
      for pkg in com.google.android.gms com.google.android.gsf; do
        timeout 40 "$ADB" shell pm disable-user --user 0 "$pkg" 2>&1 | tail -1
      done
      touch "$C/avd/.gms-disabled"
      echo "=== gms disabled $(date)"
      for j in $(seq 1 120); do
        b=$(timeout 12 "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
        [ "$b" = "1" ] && { echo "boot completed $(date)"; exit 0; }
        alive || { echo "emulator gone while waiting for boot"; exit 1; }
        sleep 5
      done
      exit 0
    else
      # maybe there is no GMS in this image, or boot finished without it
      b=$(timeout 12 "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
      if [ "$b" = "1" ] && [ -z "$p" ]; then
        echo "boot completed with no GMS present; nothing to disable"; exit 0
      fi
    fi
  fi
  alive || { echo "emulator gone"; exit 1; }
  sleep 3
done
echo "package manager never answered; exiting"
exit 1
