#!/bin/bash
# ============================================================================
# android-runtime.sh — provision the Android app environment (APK sideloading
# + HelloTalk) on the cloud Debian desktop.
#
# Host-side script (like the other deploy/ scripts). Everything lives under
# /home/z/my-project/.android-cache (gitignored, but the directory SURVIVES
# platform resets), so re-running after a reset is FAST (no re-downloads).
#
# What it builds:
#   * Android SDK emulator (userspace, no KVM needed: TCG software CPU
#     emulation + host-side SwiftShader GPU rendering) with the
#     android-30 google_apis x86_64 image (Google services + ARM
#     translation via libndk — needed because most APKs ship arm64 only)
#   * AVD "android30" (360x720 @ 240dpi window fits the desktop nicely)
#   * statvfs LD_PRELOAD shim — the emulator refuses to start with < 2 GiB
#     free disk; this sandbox is tight, so we report 64 GiB to it
#   * oom-shepherd — marks auto-reviving services as preferred OOM victims
#     (a 2.7 GiB emulator on a 3.9 GiB box needs the headroom)
#   * front-proxy android endpoints (/fapi/android, /fapi/android/start,
#     /fapi/apk-install) + desktop helpers + launchers + autostart
#   * postboot auto-installer — installs every cached APK (HelloTalk)
#     once the emulator finishes booting
#
# Env knobs: ANDROID_NO_START=1  don't launch the emulator at the end
# ============================================================================
set -u
C=/home/z/my-project/.android-cache
S=/home/z/debian/sysroot
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$C"/{sdk,avd,apks,dist,android-user} "$C"/avd/android30.avd 2>/dev/null

log() { echo "[android-runtime] $*"; }

# ---------------------------------------------------------------- 1. scripts
log "installing host scripts into $C"
for f in emulator-launch.sh avd-create.sh sdk-install.sh \
         apk-install-helper.py oom-shepherd.sh gms-disabler.sh \
         android-session.sh statvfs-shim.c; do
  [ -f "$HERE/$f" ] && cp "$HERE/$f" "$C/" && chmod +x "$C/$f" 2>/dev/null
done
# keep the cached shim binary if present (gcc may be needed to rebuild it)
[ -f "$C/dist/statvfs-shim.so" ] || cp "$HERE/statvfs-shim.so" "$C/dist/" 2>/dev/null

# ------------------------------------------------- 2. sdk (fast/slow paths)
IMGDIR="$C/sdk/system-images/android-30/google_apis/x86_64"
have_sdk() { [ -x "$C/sdk/emulator/emulator" ] && [ -f "$IMGDIR/system.img" ]; }

if ! have_sdk; then
  log "SLOW PATH: downloading the SDK (about 2.3 GB)"
  # -- bsdtar for stream-extraction (never stores the zips on disk)
  if ! command -v bsdtar >/dev/null 2>&1; then
    mkdir -p "$C/debs" && cd "$C/debs"
    apt-get download libarchive-tools >/dev/null 2>&1
    for f in *.deb; do dpkg -x "$f" ./x 2>/dev/null; done
    export PATH="$C/debs/x/usr/bin:$PATH"
  fi
  # -- userspace JDK + cmdline-tools for sdkmanager/avdmanager
  if [ ! -d "$C/jdk" ]; then
    log "  userspace OpenJDK 21"
    ( cd "$C/debs" && apt-get download openjdk-21-jre-headless >/dev/null 2>&1
      mkdir -p "$C/jdk" && for f in openjdk-21-jre-headless*.deb; do dpkg -x "$f" "$C/jdk" 2>/dev/null; done )
  fi
  JH=$(echo "$C"/jdk/usr/lib/jvm/java-21-openjdk-* 2>/dev/null | head -1)
  if [ ! -d "$C/sdk/cmdline-tools/latest" ]; then
    log "  cmdline-tools"
    curl -sL --retry 3 -o "$C/dist/clt.zip" \
      https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
    mkdir -p "$C/sdk/cmdline-tools" "$C/tmp"
    unzip -qo "$C/dist/clt.zip" -d "$C/tmp" && rm -rf "$C/sdk/cmdline-tools/latest"
    mv "$C/tmp/cmdline-tools" "$C/sdk/cmdline-tools/latest"
    rm -f "$C/dist/clt.zip"
  fi
  # -- platform-tools (adb) via sdkmanager
  log "  platform-tools (adb)"
  ( export JAVA_HOME="$JH" PATH="$JH/bin:$PATH"
    yes | timeout 300 "$C/sdk/cmdline-tools/latest/bin/sdkmanager" \
      --sdk_root="$C/sdk" platform-tools >/dev/null 2>&1 ) || log "  WARN: sdkmanager platform-tools failed"
  # -- emulator package via sdkmanager (stream-friendly alternative below if it fails)
  if [ ! -x "$C/sdk/emulator/emulator" ]; then
    log "  emulator package (~860 MB)"
    ( export JAVA_HOME="$JH" PATH="$JH/bin:$PATH"
      yes | timeout 900 "$C/sdk/cmdline-tools/latest/bin/sdkmanager" \
        --sdk_root="$C/sdk" emulator >/dev/null 2>&1 ) || true
  fi
  # -- system image: stream-extract (zip never lands on disk, ~3.3 GB raw)
  if [ ! -f "$IMGDIR/system.img" ]; then
    log "  system image (android-30 google_apis x86_64, stream-extracted)"
    mkdir -p "$C/sdk/system-images/android-30/google_apis"
    curl -sL --retry 3 \
      https://dl.google.com/android/repository/sys-img/google_apis/x86_64-30_r12.zip \
      | bsdtar -xf- -C "$C/sdk/system-images/android-30/google_apis" \
        'x86_64' 'x86_64/*' 2>/dev/null \
      || log "  ERROR: image extraction failed"
  fi

  # -- AVD (needs java, so create before dropping the JDK)
  [ -f "$C/avd/android30.avd/config.ini" ] || bash "$C/avd-create.sh" || true

  # -- HelloTalk (latest) via apkeep from APKPure
  if ! ls "$C"/apks/com.hellotalk.* >/dev/null 2>&1; then
    log "  downloading HelloTalk (latest) from APKPure"
    [ -x "$C/dist/apkeep" ] || {
      curl -sL -o "$C/dist/apkeep" \
        https://github.com/EFForg/apkeep/releases/download/1.1.0/apkeep-x86_64-unknown-linux-gnu
      chmod +x "$C/dist/apkeep"; }
    ( cd "$C/apks" && timeout 600 "$C/dist/apkeep" -a com.hellotalk \
        -d apk-pure -o acknowledge_dangers=true . ) || log "  WARN: HelloTalk download failed"
  fi

  # -- disk hygiene: this box only has ~10 GB total
  log "  trimming fat (qemu arch variants, netsimd, holes, sysroot docs)"
  Q="$C/sdk/emulator/qemu/linux-x86_64"
  for b in qemu-system-aarch64 qemu-system-aarch64-headless qemu-system-armel \
           qemu-system-armel-headless qemu-system-i386 qemu-system-i386-headless \
           qemu-system-x86_64-headless; do rm -f "$Q/$b"; done
  rm -rf "$C/sdk/emulator/netsimd" 2>/dev/null
  for f in system.img vendor.img userdata.img; do
    fallocate --dig-holes "$IMGDIR/$f" 2>/dev/null
  done
  rm -rf "$S/usr/share/doc" "$S/usr/share/man" "$S/usr/share/help" \
         "$S/usr/share/gtk-doc" "$S/usr/share/speech-dispatcher" \
         "$S/usr/share/cmake-3.31" "$S/usr/share/nmap" 2>/dev/null
  find "$S/usr/share/locale" -maxdepth 1 -mindepth 1 -type d ! -name 'en*' \
       -exec rm -rf {} + 2>/dev/null
  find "$S/usr/share/backgrounds/gnome" -maxdepth 1 -type f \
       \( -name '*.jxl' -o -name '*.jpg' -o -name '*.svg' \) -delete 2>/dev/null
  # drop the provisioning-only toolchain (re-downloadable, saves ~350 MB)
  rm -rf "$C/jdk" "$C/sdk/cmdline-tools" "$C/debs" "$C/tmp" 2>/dev/null
else
  log "FAST PATH: cached SDK found"
fi

# ------------------------------------------------------ 3. statvfs shim
if [ ! -f "$C/dist/statvfs-shim.so" ]; then
  log "compiling statvfs shim (emulator disk-space check bypass)"
  if [ -x "$S/usr/bin/gcc" ]; then
    cp "$C/statvfs-shim.c" /tmp/statvfs-shim.c
    /home/z/debian/bin/debian-session /usr/bin/gcc -shared -fPIC -O2 \
      -o /tmp/statvfs-shim.so /tmp/statvfs-shim.c -ldl \
      && cp /tmp/statvfs-shim.so "$C/dist/statvfs-shim.so"
  fi
fi
[ -f "$C/dist/statvfs-shim.so" ] || log "WARN: no statvfs shim (emulator may refuse to start on low disk)"

# --------------------------------------------------------- 4. oom-shepherd
if ! pgrep -f oom-shepherd >/dev/null 2>&1; then
  log "starting oom-shepherd"
  ( setsid nohup bash "$C/oom-shepherd.sh" > "$C/oom-shepherd.log" 2>&1 < /dev/null & )
fi

# ---------------------------------------------- 5. desktop (sysroot) bits
log "installing desktop helpers + launchers"
install -m 755 "$HERE/bin/android-start"   "$S/usr/local/bin/android-start"
install -m 755 "$HERE/bin/android-install" "$S/usr/local/bin/android-install"
install -m 755 "$HERE/bin/android-status"  "$S/usr/local/bin/android-status"
mkdir -p "$S/usr/local/share/icons/hicolor/256x256/apps"
install -m 644 "$HERE/icons/android-emulator.png" \
               "$HERE/icons/apk-install.png" \
               "$S/usr/local/share/icons/hicolor/256x256/apps/"
DB="$S/home/debian/Desktop"
mkdir -p "$DB" "$S/home/debian/.config/autostart"
install -m 644 "$HERE/desktop/Android.desktop"       "$DB/Android.desktop"
install -m 644 "$HERE/desktop/Install-APK.desktop"   "$DB/Install-APK.desktop"
install -m 644 "$HERE/desktop/android-autostart.desktop" \
               "$S/home/debian/.config/autostart/android-autostart.desktop"

# mark the new desktop launchers trusted (retry: gvfs metadata daemon must
# be on the session bus first — gio set fails silently otherwise)
GIO_SH="$S/usr/local/bin/.android-trust.sh"
cat > "$GIO_SH" <<'EOS'
#!/bin/bash
export HOME=/home/debian
unset LD_PRELOAD
for f in /home/debian/Desktop/Android.desktop /home/debian/Desktop/Install-APK.desktop; do
  [ -f "$f" ] || continue
  ok=""
  for i in 1 2 3 4 5 6; do
    gio set "$f" metadata::trusted true 2>/dev/null
    gio info "$f" 2>/dev/null | grep -q 'metadata::trusted.*true' && ok=1 && break
    sleep 5
  done
  [ -n "$ok" ] && touch "$f"
done
EOS
chmod +x "$GIO_SH"
( setsid nohup /home/z/debian/bin/debian-session /usr/local/bin/.android-trust.sh \
    > "$C/avd/trust.log" 2>&1 < /dev/null & )

# ------------------------------------------- 6. debian-status android check
DS=/home/z/debian/bin/debian-status
if [ -f "$DS" ] && ! grep -q 'android runtime' "$DS"; then
  cat >> "$DS" <<'EOS'

# Android runtime (userspace emulator)
if curl -s -m 5 http://127.0.0.1:3000/fapi/android 2>/dev/null | grep -q '"provisioned": *true'; then
  RUN=$(curl -s -m 5 http://127.0.0.1:3000/fapi/android 2>/dev/null | grep -o '"running": *[a-z]*' | head -1 | grep -o 'true\|false')
  ok "android runtime provisioned (emulator ${RUN:-unknown})"
else
  bad "android runtime not reachable via front-proxy"
fi
EOS
  log "debian-status: android check added"
fi

# ------------------------------------- 7. front-proxy must know /fapi/android
if curl -s -m 5 http://127.0.0.1:3000/fapi/android 2>/dev/null | grep -q '"provisioned"'; then
  log "front-proxy android endpoints OK"
else
  NEW=/home/z/debian/bin/front-proxy
  SRC=$(dirname "$HERE")/gnome-runtime/front-proxy.py
  if [ -f "$SRC" ]; then
    log "updating front-proxy with android endpoints + restarting it"
    cp "$SRC" "$NEW" && chmod +x "$NEW"
    pkill -f front-proxy 2>/dev/null   # supervisor revives it within ~6s
    sleep 8
  fi
fi

# ------------------------------------------------------- 8. launch
if [ "${ANDROID_NO_START:-0}" != "1" ]; then
  log "starting the Android emulator (boot takes ~8-14 min on 1 software core)"
  bash "$C/emulator-launch.sh" || true
  ( setsid nohup bash "$C/android-session.sh" > /dev/null 2>&1 < /dev/null & )
fi
log "done."
