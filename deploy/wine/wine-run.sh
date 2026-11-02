#!/bin/bash
# ============================================================================
# wine-run — launch a Windows program on the cloud Debian desktop.
# HOST-side helper (deployed to /home/z/debian/bin/wine-run by
# wine-runtime.sh). Called by the front-proxy /fapi/wine endpoints and
# safe to call from any host shell.
#
# Usage:
#   wine-run 7zip        # 7-Zip File Manager
#   wine-run notepad++   # Notepad++
#   wine-run winecfg     # Wine configuration
#   wine-run /home/debian/Downloads/app.exe [args...]   # any .exe
#
# Runs inside the Debian sysroot via fakechroot (debian-session trampoline),
# on the shared X display :1, fully detached so it survives proxy restarts.
# Single instance per app via pidfile (basenames contain regex-hostile chars).
# ============================================================================
set -u
BASE=/home/z/debian
S=$BASE/sysroot
PREFIX=/home/debian/.wine

# ---------------------------------------------------------- wine binary ---
# Debian trixie: /usr/bin/wine (alternatives), /usr/bin/wine-stable
# (wrapper), or /usr/lib/wine/wine64 (raw loader)
WINE=/usr/bin/wine
[ -x "$S$WINE" ] || WINE=/usr/bin/wine-stable
[ -x "$S$WINE" ] || WINE=/usr/bin/wine64
[ -x "$S$WINE" ] || { echo "wine-run: wine not installed in sysroot" >&2; exit 1; }

# ------------------------------------------------------------- keyword ----
APP=""
case "${1:-}" in
  7zip)      APP="$PREFIX/drive_c/Program Files/7-Zip/7zFM.exe" ;;
  notepad++) APP="$PREFIX/drive_c/Program Files/Notepad++/notepad++.exe" ;;
  winecfg)   APP="__WINECFG__" ;;
  -h|--help)
    echo "usage: wine-run 7zip|notepad++|winecfg|<path-to-exe> [args...]"
    exit 0 ;;
  *)         APP="${1:-}" ;;
esac
[ -n "$APP" ] || { echo "wine-run: missing argument" >&2; exit 1; }

# ------------------------------------------------------------- env --------
run_env() {
  env HOME=/home/debian USER=debian LOGNAME=debian SHELL=/bin/bash \
      DISPLAY=:1 LANG=en_US.UTF-8 \
      XDG_RUNTIME_DIR=/run/user/1001 \
      WINEPREFIX="$PREFIX" WINEARCH=win64 \
      WINEDEBUG=-all \
      WINEDLLOVERRIDES="mscoree,mshtml=" \
      LIBGL_ALWAYS_SOFTWARE=1 \
      "$BASE/bin/debian-session" "$@"
}

# ------------------------------------------------------- single instance --
tag=""
if [ "$APP" != "__WINECFG__" ]; then
  tag=$(basename "$APP" | tr -c 'A-Za-z0-9' '_' | cut -c1-40)
  PIDF="$BASE/run/wine-$tag.pid"
  if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then
    echo "wine-run: $(basename "$APP") already running (pid $(cat "$PIDF"))"
    exit 0
  fi
fi

mkdir -p "$S/run" 2>/dev/null
LOG="$BASE/run/wine-$(date +%s).log"

if [ "$APP" = "__WINECFG__" ]; then
  setsid nohup run_env "$WINE" winecfg.exe \
    > "$LOG" 2>&1 < /dev/null &
else
  # the exe must exist inside the sysroot (wine resolves chroot paths)
  if [ ! -e "$S$APP" ]; then
    echo "wine-run: not found in sysroot: $APP" >&2
    exit 1
  fi
  [ $# -gt 0 ] && shift
  setsid nohup run_env "$WINE" "$APP" "$@" \
    > "$LOG" 2>&1 < /dev/null &
fi
PID=$!
[ -n "$tag" ] && echo "$PID" > "$BASE/run/wine-$tag.pid" 2>/dev/null
echo "wine-run: launched $(basename "$APP") (pid $PID) — display :1"
