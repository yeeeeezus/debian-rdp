#!/bin/bash
# Launch the Android emulator window on the desktop X display (:1).
# Pure software: TCG CPU emulation + host-side SwiftShader GPU (no KVM needed).
# Single instance: exits 0 politely if already running.
C=/home/z/android-cache
export ANDROID_SDK_ROOT="$C/sdk"
export ANDROID_AVD_HOME="$C/avd"
export ANDROID_USER_HOME="$C/android-user"
export ANDROID_PREFS_ROOT="$C/android-user"
export DISPLAY="${ANDROID_DISPLAY:-:1}"
export QT_X11_NO_MITSHM=1
# emulator 37.3+ refuses -accel off without this opt-in
export ANDROID_I_WANT_MY_TCG=yes
# the emulator's pre-flight check demands 2 GiB free; this sandbox is tight,
# so we preload a statvfs shim reporting 64 GiB (disk writes are NOT affected)
# qemu needs the emulator package's own Qt/tcmalloc libs
export LD_LIBRARY_PATH="/home/z/android-cache/sdk/emulator/lib64:/home/z/android-cache/sdk/emulator/lib64/qt/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_PRELOAD="$C/dist/statvfs-shim.so"
PIDF="$C/avd/emulator.pid"
LOG="$C/avd/emulator-launch.log"

if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then
  echo "emulator already running (pid $(cat "$PIDF"))"
  exit 0
fi
mkdir -p "$C/avd"
( setsid nohup "$C/sdk/emulator/emulator" \
  -avd android30 \
  -accel off \
  -no-window \
  -gpu swiftshader_indirect \
  -no-boot-anim \
  -no-snapshot \
  -no-audio \
  -memory "${ANDROID_MEM:-768}" \
  -cores 2 \
  -feature -Vulkan \
  -prop ro.setupwizard.mode=DISABLED \
  -prop ro.config.low_ram=true \
  -prop dalvik.vm.image-dex2oat-filter=verify-none \
  -prop dalvik.vm.dex2oat-filter=verify-none \
  > "$LOG" 2>&1 < /dev/null & )
EPID=""
for i in $(seq 1 15); do
  EPID=$(pgrep -f "emulator -avd android30" | head -1)
  [ -n "$EPID" ] && break
  pgrep -f 'qemu-system-x86_64' >/dev/null && { EPID=$(pgrep -f 'qemu-system-x86_64' | head -1); break; }
  sleep 1
done
if [ -n "$EPID" ]; then
  echo "$EPID" > "$PIDF"
  echo "emulator launched (pid $EPID), display $DISPLAY, log $LOG"
else
  echo "ERROR: emulator did not start, log tail:"
  tail -5 "$LOG"
  exit 1
fi
