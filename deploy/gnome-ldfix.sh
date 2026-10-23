#!/bin/bash
# ============================================================================
# gnome-ldfix.sh - ldconfig cannot run as non-root here; ld.so without a
# cache only searches DEFAULT dirs. GNOME packages install helper libs into
# non-default subdirs (gvfs/, gnome-settings-daemon-3.0/, localsearch/,
# gnome-software/, ...) that on a real system are found via RUNPATH/$ORIGIN -
# which fakechroot does not translate for ld.so's internal opens.
# Fix: symlink every .so* from every non-default lib dir into the default
# multiarch dir. Idempotent - safe to re-run after every extraction.
# ============================================================================
set -u
S=/home/z/debian/sysroot
DEF=$S/usr/lib/x86_64-linux-gnu

# 1) dirs registered in /etc/ld.so.conf.d/*.conf (one include level)
DIRS=$(cat $S/etc/ld.so.conf.d/*.conf 2>/dev/null | grep -vE '^\s*#|^\s*$' | sed 's/^include //' | sort -u)

# 2) every direct subdir of the multiarch dir AND /usr/lib that contains .so
for d in "$DEF"/*/ "$S"/usr/lib/*/; do
  d=${d%/}
  [ -d "$d" ] || continue
  case "$(basename "$d")" in
    fakechroot|x86_64-linux-gnu|i386-linux-gnu) continue ;;
  esac
  ls "$d"/*.so* >/dev/null 2>&1 && DIRS="$DIRS ${d#"$S"}"
done
# 3) known extra runtime dirs
DIRS="$DIRS /usr/lib/x86_64-linux-gnu/gvfs /usr/lib/x86_64-linux-gnu/gnome-settings-daemon-3.0 /usr/lib/x86_64-linux-gnu/localsearch /usr/lib/x86_64-linux-gnu/gnome-software"

N=0
for d in $DIRS; do
  case "$d" in
    /usr/lib/x86_64-linux-gnu|/lib/x86_64-linux-gnu|/usr/lib|/lib|/usr/local/lib|/usr/local/lib/x86_64-linux-gnu) continue ;;
  esac
  sd="$S$d"
  [ -d "$sd" ] || continue
  for so in "$sd"/*.so*; do
    [ -e "$so" ] || continue
    base=$(basename "$so")
    if [ -e "$DEF/$base" ] && [ ! -L "$DEF/$base" ]; then continue; fi   # real file in default dir wins
    # symlink target MUST be RELATIVE (ld.so opens bypass fakechroot translation)
    case "$d" in
      /usr/lib/x86_64-linux-gnu/*) rel="${d#/usr/lib/x86_64-linux-gnu/}/$base" ;;
      /usr/lib/*)                   rel="../${d#/usr/lib/}/$base" ;;
      *)                            rel="$(echo "$d" | sed 's|^/usr/lib/x86_64-linux-gnu|.|')/$base" ;;
    esac
    ln -sfn "$rel" "$DEF/$base" 2>/dev/null && N=$((N+1)) || true
  done
done
echo "ldfix: $N new symlinks into /usr/lib/x86_64-linux-gnu/"

# verify the known-critical ones
for lib in libgvfscommon.so libgsd.so libtracker-extract.so libgnomesoftware.so.22; do
  [ -e "$DEF/$lib" ] && echo "ldfix OK: $lib" || echo "ldfix STILL MISSING: $lib"
done
