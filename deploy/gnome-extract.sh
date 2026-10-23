#!/bin/bash
# ============================================================================
# gnome-extract.sh - extract ALL cached debs into the Debian 13 sysroot,
# then regenerate the postinst-generated caches (GLib schemas, icons, mime,
# desktop db, fonts). Idempotent - safe to re-run.
# ============================================================================
set -u
BASE=/home/z/debian
S=$BASE/sysroot
DEBS=$BASE/debs

count=0; failed=0
for f in "$DEBS"/*.deb; do
  if dpkg -x "$f" "$S" 2>/dev/null; then
    count=$((count+1))
  else
    failed=$((failed+1)); echo "FAILED: $f"
  fi
done
echo "=== Extracted $count packages ($failed failed) ==="
du -sh "$S"

# fakechroot environment for running inner binaries
export LD_LIBRARY_PATH="$S/usr/lib/x86_64-linux-gnu:$S/lib/x86_64-linux-gnu"
export LD_PRELOAD="$S/usr/lib/x86_64-linux-gnu/fakechroot/libfakechroot.so"
export FAKECHROOT_EXCLUDE_PATH="/dev:/proc:/sys:/tmp"
CHROOT=/usr/sbin/chroot; [ -x "$CHROOT" ] || CHROOT=/usr/bin/chroot
FC() { "$CHROOT" "$S" "$@"; }

echo "== GLib schemas (MUST succeed for GNOME) =="
FC glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>&1 | tail -3

echo "== GTK icon caches =="
if [ -x "$S/usr/bin/gtk-update-icon-cache" ]; then
  for d in "$S"/usr/share/icons/*; do
    [ -d "$d" ] || continue
    FC gtk-update-icon-cache -q -t -f "/usr/share/icons/$(basename "$d")" 2>/dev/null || true
  done
else
  echo "(gtk-update-icon-cache not present - skipping, GTK will scan fs)"
fi

echo "== mime database =="
FC update-mime-database /usr/share/mime 2>&1 | tail -1 || true

echo "== desktop database =="
FC update-desktop-database /usr/share/applications 2>&1 | tail -1 || true

echo "== font cache (background) =="
FC fc-cache -f >/dev/null 2>&1 &

echo "== GNOME key paths check =="
for p in usr/bin/gnome-shell usr/bin/gnome-session usr/bin/nautilus \
         usr/bin/gsettings usr/bin/dconf usr/share/xsessions/gnome-xorg.desktop \
         usr/share/xsessions/gnome.desktop usr/libexec/gnome-session-binary \
         usr/libexec/gsd-* ; do
  ls $S/$p >/dev/null 2>&1 && echo "OK   $p" || echo "MISS $p"
done | sort | uniq -c | sort -rn | head -8
for p in usr/bin/gnome-shell usr/bin/gnome-session usr/bin/nautilus usr/bin/gsettings; do
  [ -e "$S/$p" ] && echo "OK   $p" || echo "MISS $p"
done
echo "== GNOME session files =="
ls "$S"/usr/share/xsessions/ 2>/dev/null
echo "== done =="
