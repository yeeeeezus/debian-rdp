#!/bin/bash
# ============================================================================
# gnome-dconf-seed.sh - system-wide dconf defaults for the RDP GNOME session.
# Compiles /etc/dconf/db/local from keyfiles so settings apply at FIRST shell
# start (no bus needed at compile time). Boot-critical items live here:
# mutter experimental features OFF (scale-monitor breaks on Xvnc), animations
# OFF (VNC speed), lock/screensaver OFF, wallpaper, favorites, DING extension.
# Idempotent - safe to re-run.
# ============================================================================
set -u
S=/home/z/debian/sysroot

mkdir -p $S/etc/dconf/profile $S/etc/dconf/local.d

cat > $S/etc/dconf/profile/user << 'EOF'
user-db:user
system-db:local
EOF

cat > $S/etc/dconf/local.d/00-rdp-defaults << 'EOF'
# Boot-critical defaults for the VNC-hosted GNOME session

[org/gnome/mutter]
# scale-monitor-framebuffer + xwayland-native-scaling break rendering on Xvnc
experimental-features=@as []

[org/gnome/desktop/interface]
enable-animations=false
clock-show-date=true
clock-show-weekday=true
clock-show-seconds=false
color-scheme='default'

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
lock-enabled=false
idle-activation-enabled=false

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
idle-dim=false

[org/gnome/desktop/background]
picture-uri='file:///usr/share/desktop-base/ceratopsian-theme/wallpaper/contents/images/1920x1080.svg'
picture-uri-dark='file:///usr/share/desktop-base/ceratopsian-theme/wallpaper/contents/images/1920x1080.svg'
picture-options='zoom'
primary-color='#241f31'

[org/gnome/shell]
favorite-apps=['firefox-esr.desktop', 'org.gnome.Ptyxis.desktop', 'org.gnome.Nautilus.desktop', 'libreoffice-writer.desktop', 'org.remmina.Remmina.desktop']
enabled-extensions=['ding@rastersoft.com']
disable-user-extensions=false

[org/gnome/desktop/peripherals/mouse]
tap-to-click=true

[org/freedesktop/Tracker3/Miner/Files]
enable-crawling=false
enable-monitors=false
EOF

# compile the database (runs inside fakechroot)
export LD_LIBRARY_PATH="$S/usr/lib/x86_64-linux-gnu:$S/lib/x86_64-linux-gnu"
export LD_PRELOAD="$S/usr/lib/x86_64-linux-gnu/fakechroot/libfakechroot.so"
export FAKECHROOT_EXCLUDE_PATH="/dev:/proc:/sys:/tmp"
CHROOT=/usr/sbin/chroot; [ -x "$CHROOT" ] || CHROOT=/usr/bin/chroot
"$CHROOT" "$S" dconf compile /etc/dconf/db/local /etc/dconf/local.d \
  && echo "dconf seed compiled OK" || echo "dconf compile FAILED"
