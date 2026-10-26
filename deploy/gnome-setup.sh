#!/bin/bash
# ============================================================================
# gnome-setup.sh - ONE script that turns a freshly-extracted sysroot into the
# working GNOME RDP system. Run AFTER gnome-download.sh + gnome-extract.sh.
# Consolidates: base system files, system users (CRITICAL: messagebus),
# ld.so fixups, dconf seed, runtime scripts, Mininet lab, Firefox seed,
# VNC password, noVNC page, host-side service scripts.
# Idempotent - safe to re-run.  Runs HOST-side.
# ============================================================================
set -u
BASE=/home/z/debian
S=$BASE/sysroot
H=$S/home/debian
DEPLOY="$(cd "$(dirname "$0")" && pwd)"

echo "== 1. base system files =="
if [ ! -s $S/etc/passwd ] || ! grep -q '^root:' $S/etc/passwd; then
  [ -f $S/usr/share/base-passwd/passwd.master ] && cp $S/usr/share/base-passwd/passwd.master $S/etc/passwd
fi
if [ ! -s $S/etc/group ] || ! grep -q '^root:' $S/etc/group; then
  [ -f $S/usr/share/base-passwd/group.master ] && cp $S/usr/share/base-passwd/group.master $S/etc/group
fi
grep -q '^debian:' $S/etc/passwd || echo 'debian:x:1001:1001:Debian User,,,:/home/debian:/bin/bash' >> $S/etc/passwd
grep -q '^debian:' $S/etc/group  || echo 'debian:x:1001:' >> $S/etc/group
mkdir -p $S/usr/local/{bin,etc,include,lib,sbin,share,src,games}
[ -e $S/var/run ] || ln -s /run $S/var/run
[ -e $S/var/lock ] || ln -s /run/lock $S/var/lock
[ -e $S/etc/mtab ] || ln -s /proc/mounts $S/etc/mtab
[ -s $S/etc/machine-id ] || tr -d '-' < /proc/sys/kernel/random/uuid > $S/etc/machine-id
mkdir -p $S/var/lib/dbus; cp -f $S/etc/machine-id $S/var/lib/dbus/machine-id
ln -sf /usr/share/zoneinfo/Asia/Damascus $S/etc/localtime
echo 'Asia/Damascus' > $S/etc/timezone
echo 'LANG=en_US.UTF-8' > $S/etc/default/locale
echo 'en_US.UTF-8 UTF-8' > $S/etc/locale.gen
# generate the locale (postinst never ran; without it apps fall back to C)
export LD_LIBRARY_PATH="$S/usr/lib/x86_64-linux-gnu:$S/lib/x86_64-linux-gnu"
export LD_PRELOAD="$S/usr/lib/x86_64-linux-gnu/fakechroot/libfakechroot.so"
export FAKECHROOT_EXCLUDE_PATH="/dev:/proc:/sys:/tmp"
/usr/sbin/chroot "$S" /usr/sbin/locale-gen >/dev/null 2>&1 || echo "WARN: locale-gen failed"
unset LD_PRELOAD
touch $S/etc/fstab
cp -f /etc/resolv.conf $S/etc/resolv.conf
echo 'debian-pc' > $S/etc/hostname

# alternatives symlinks (normally created by postinst)
ln -sf dash      $S/usr/bin/sh
ln -sf mawk      $S/usr/bin/awk
ln -sf vim.basic $S/usr/bin/vi
ln -sf gcc-14 $S/usr/bin/gcc 2>/dev/null
ln -sf g++-14 $S/usr/bin/g++ 2>/dev/null
ln -sf gcc   $S/usr/bin/cc   2>/dev/null
ln -sf g++   $S/usr/bin/c++  2>/dev/null
# 'which' was dropped from trixie; mininet needs it
[ -x $S/usr/bin/which ] || printf '#!/bin/sh\ncommand -v -- "$@"\n' > $S/usr/bin/which && chmod +x $S/usr/bin/which

echo "== 2. system users (messagebus is CRITICAL for the system dbus) =="
for entry in \
  'messagebus:x:101:101:DBus message bus user:/nonexistent:/usr/sbin/nologin' \
  'polkitd:x:102:102:PolicyKit daemon:/nonexistent:/usr/sbin/nologin' \
  'colord:x:103:103:Color management daemon:/nonexistent:/usr/sbin/nologin' \
  'geoclue:x:104:104:Geolocation service:/nonexistent:/usr/sbin/nologin' \
  'Debian-gdm:x:105:105:GDM display manager:/var/lib/gdm3:/usr/sbin/nologin' \
  'systemd-network:x:106:106:systemd Network Management:/nonexistent:/usr/sbin/nologin' \
  'systemd-resolve:x:107:107:systemd Resolver:/nonexistent:/usr/sbin/nologin'; do
  n=${entry%%:*}; grep -q "^$n:" $S/etc/passwd || echo "$entry" >> $S/etc/passwd
done
for g in messagebus:101 polkitd:102 colord:103 geoclue:104 Debian-gdm:105 systemd-network:106 systemd-resolve:107; do
  n=${g%%:*}; grep -q "^$n:" $S/etc/group || echo "$g:x:${g##*:}:" >> $S/etc/group
done
awk -F: '!/^#/ && NF==7 {print $1":*:20000:0:99999:7:::"}' $S/etc/passwd > $S/etc/shadow
chmod 640 $S/etc/shadow

echo "== 3. ld.so fixups + dconf seed (separate scripts) =="
bash "$DEPLOY/gnome-ldfix.sh" | tail -5
bash "$DEPLOY/gnome-dconf-seed.sh" | tail -1

echo "== 4. inner runtime scripts =="
for f in session-inner gnome-start gnome-polish; do
  cp "$DEPLOY/gnome-runtime/$f" $S/usr/local/bin/ && chmod +x $S/usr/local/bin/$f
done
# mininet lab (userns + linux-bridge switch)
mkdir -p $S/usr/local/lib/mininet-lab
cp "$DEPLOY"/mininet/mn "$DEPLOY"/mininet/mnexec "$DEPLOY"/mininet/mininet-lab $S/usr/local/bin/ 2>/dev/null
cp "$DEPLOY"/mininet/lxbr.py "$DEPLOY"/mininet/labrc $S/usr/local/lib/mininet-lab/ 2>/dev/null
chmod +x $S/usr/local/bin/{mn,mnexec,mininet-lab} 2>/dev/null

echo "== 5. noVNC perfect-fit page =="
cp "$DEPLOY/gnome-runtime/novnc-index.html" $S/usr/share/novnc/index.html
# official Debian swirl: favicon + apple-touch + boot-screen logo
cp "$DEPLOY/assets/debian-swirl.svg" "$DEPLOY/assets/favicon-32.png" \
   "$DEPLOY/assets/favicon-64.png" "$DEPLOY/assets/apple-touch-icon.png" \
   $S/usr/share/novnc/

echo "== 6. home skeleton + Firefox tuned profile + VNC password =="
mkdir -p $H/{Desktop,Documents,Downloads,Music,Pictures,Videos,Templates,Public} $H/.vnc $H/.config/autostart
mkdir -p "$DEPLOY/assets"; if [ -f "$DEPLOY/assets/vnc-passwd" ]; then cp "$DEPLOY/assets/vnc-passwd" $H/.vnc/passwd; chmod 600 $H/.vnc/passwd; elif [ -f /tmp/rdp-data-clone/vnc/passwd ]; then cp /tmp/rdp-data-clone/vnc/passwd $H/.vnc/passwd; chmod 600 $H/.vnc/passwd; else echo "WARN: no vnc-passwd staged (run bootstrap.sh with token)"; fi
# gsd-Power autostart off (UPower/polkit impossible here)
cat > $H/.config/autostart/org.gnome.SettingsDaemon.Power.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Power management (disabled - no UPower in container)
Hidden=true
EOF
mkdir -p $H/.mozilla/firefox/zcloud.default-esr
cat > $H/.mozilla/firefox/profiles.ini << 'EOF'
[General]
StartWithLastProfile=1

[Profile0]
Name=default-esr
IsRelative=1
Path=zcloud.default-esr
Default=1
EOF
cat > $H/.mozilla/firefox/zcloud.default-esr/user.js << 'EOF'
user_pref("general.smoothScroll", false);
user_pref("toolkit.scrollbox.smoothScroll", false);
user_pref("toolkit.cosmeticAnimations.enabled", false);
user_pref("browser.sessionstore.interval", 300000);
user_pref("dom.ipc.processCount", 3);
user_pref("browser.pagethumbnails.capturing_disabled", true);
user_pref("layout.frame_rate", 40);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
EOF

echo "== 7. host-side service scripts =="
mkdir -p $BASE/bin $BASE/run $BASE/logs
for f in debian-supervisor debian-status debian-session debian-start debian-stop rdp-keepalive; do
  cp "$DEPLOY/gnome-runtime/$f" $BASE/bin/ && chmod +x $BASE/bin/$f
done
cp "$DEPLOY/gnome-runtime/rdp-save-daemon" "$DEPLOY/gnome-runtime/rdp-repos-setup.sh" $BASE/bin/ && chmod +x $BASE/bin/rdp-save-daemon $BASE/bin/rdp-repos-setup.sh
mkdir -p $BASE/run $BASE/logs

echo "== 8. desktop integration (vault, launchers, helpers) =="
bash "$DEPLOY/gnome-desktop-integration.sh" | tail -3

echo "== setup complete =="

echo "== 9. gdk-pixbuf loaders cache (postinst never ran; SVG/wallpapers need it) =="
export LD_LIBRARY_PATH="$S/usr/lib/x86_64-linux-gnu:$S/lib/x86_64-linux-gnu"
export LD_PRELOAD="$S/usr/lib/x86_64-linux-gnu/fakechroot/libfakechroot.so"
export FAKECHROOT_EXCLUDE_PATH="/dev:/proc:/sys:/tmp"
/usr/sbin/chroot "$S" /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders \
  > "$S/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache" 2>/dev/null || true
unset LD_PRELOAD
