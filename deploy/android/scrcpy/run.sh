#!/bin/bash
# scrcpy view of the headless Android emulator, on the desktop X display.
# Single instance; gentle settings for the software-emulated guest.
C=/home/z/my-project/.android-cache
export DISPLAY="${ANDROID_DISPLAY:-:1}"
export PATH="$C/sdk/platform-tools:$PATH"
export LD_LIBRARY_PATH="$C/scrcpy/x/usr/lib/x86_64-linux-gnu"
export ADB="$C/sdk/platform-tools/adb"
export SCRCPY_SERVER_PATH="$C/scrcpy/x/usr/share/scrcpy/scrcpy-server"
# wait briefly for a device (scrcpy exits if none)
for i in $(seq 1 60); do
  state=$("$C/sdk/platform-tools/adb" get-state 2>/dev/null | tr -d '\r')
  [ "$state" = "device" ] && break
  sleep 5
done
exec "$C/scrcpy/x/usr/bin/scrcpy" \
  --window-title "Android" \
  --max-size 720 \
  --max-fps 15 \
  --video-bit-rate 2M \
  --stay-awake \
  -s emulator-5554
