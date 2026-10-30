#!/bin/bash
# Create the android30 AVD (idempotent) with a desktop-friendly small skin.
C=/home/z/my-project/.android-cache
export JAVA_HOME="$C/jdk/usr/lib/jvm/java-21-openjdk-amd64"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_AVD_HOME="$C/avd"
export ANDROID_USER_HOME="$C/android-user"
mkdir -p "$ANDROID_AVD_HOME" "$ANDROID_USER_HOME"

echo no | "$C/sdk/cmdline-tools/latest/bin/avdmanager" create avd -n android30 \
  -k "system-images;android-30;google_apis;x86_64" --force

INI="$ANDROID_AVD_HOME/android30.avd/config.ini"
if [ -f "$INI" ]; then
  # strip keys we own, then append our overrides (INI: last value wins)
  sed -i -E '/^(hw\.lcd\.(width|height|density)|skin\.name|skin\.path|skin\.dynamic|showDeviceFrame|hw\.ramSize|hw\.keyboard|hw\.mainKeys|disk\.dataPartition\.size|vm\.heapSize)=/d' "$INI"
  cat >> "$INI" <<EOF
hw.lcd.width=360
hw.lcd.height=720
hw.lcd.density=240
skin.name=360x720
skin.path=360x720
skin.dynamic=yes
showDeviceFrame=no
hw.ramSize=1536
vm.heapSize=256
hw.keyboard=yes
hw.mainKeys=yes
disk.dataPartition.size=1536M
EOF
  echo "AVD created, config:"
  grep -E '^(hw\.lcd|skin|hw\.ramSize|disk\.data)' "$INI"
else
  echo "ERROR: config.ini not found at $INI"
  exit 1
fi
