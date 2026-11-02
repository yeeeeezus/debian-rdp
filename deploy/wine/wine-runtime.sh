#!/bin/bash
# ============================================================================
# wine-runtime.sh — provision the Windows app environment (Wine) on the
# cloud Debian desktop.
#
# Host-side script (like deploy/android/android-runtime.sh). Wine itself is
# a native sysroot package (wine + wine64 in gnome-download.sh's PKGS list,
# extracted into the sysroot by every rebuild). This script finishes the
# setup after the desktop is up:
#
#   * WINEPREFIX  /home/debian/.wine  (win64, mono/gecko prompts suppressed)
#   * 7-Zip       real Windows app, silent-installed into the prefix
#                 (official ip7z/7zip GitHub release, 7z*-x64.exe /S)
#   * Notepad++   real Windows app, portable x64 zip straight into the prefix
#                 (official notepad-plus-plus/notepad-plus-plus release)
#   * desktop launchers (7-Zip / Notepad++ / Wine config) + "Run EXE"
#     file association so double-clicking any .exe in Files opens it with Wine
#   * front-proxy /fapi/wine endpoints (status/app/run)
#   * debian-status wine check
#
# Self-healing: if Wine is missing from the sysroot (older build), the full
# wine closure is downloaded + extracted here (same unprivileged apt trick
# as gnome-download.sh — debs cached in /home/z/debian/debs, shared).
#
# Env knobs: WINE_NO_APPS=1  skip the demo apps (prefix + integration only)
# ============================================================================
set -u
BASE=/home/z/debian
S=$BASE/sysroot
DEBS=$BASE/debs
LISTS=$BASE/aptlists
EMPTY_STATUS=$BASE/empty-status
PREFIX_REL=/home/debian/.wine
PREFIX="$S$PREFIX_REL"
HERE=$(cd "$(dirname "$0")" && pwd)
DL=/home/z/my-project/.wine-dl

log() { echo "[wine-runtime] $*"; }
mkdir -p "$DL" 2>/dev/null

# ------------------------------------------------------------- 0. preflight
[ -d "$S/usr/bin" ] || { log "FATAL: sysroot not present — run bootstrap first"; exit 1; }

wine_bin() {  # prints the chroot-relative wine binary, or nothing
  # Debian trixie ships wrapper scripts with a -stable suffix (plain names
  # are created by update-alternatives postinst, which dpkg -x never runs)
  for b in /usr/bin/wine /usr/bin/wine-stable /usr/bin/wine64; do
    [ -x "$S$b" ] && { echo "$b"; return 0; }
  done
  return 1
}

# ------------------------------------------------- 1. wine present? (self-heal)
WINE=$(wine_bin || true)
if [ -z "$WINE" ]; then
  log "wine missing from sysroot — downloading the closure (self-heal)"
  mkdir -p "$DEBS/partial"
  : > "$EMPTY_STATUS" 2>/dev/null
  apt-get -o Debug::NoLocking=1 \
    -o Dir::State::lists="$LISTS" \
    -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/debian.sources \
    -o Dir::Etc::sourceparts=/nonexistent \
    -o Dir::Cache="$LISTS" \
    -o APT::Get::List-Cleanup=0 \
    update >/dev/null 2>&1
  apt-get install --download-only -y \
    -o Debug::NoLocking=1 \
    -o Dir::State::lists="$LISTS" \
    -o Dir::State::status="$EMPTY_STATUS" \
    -o Dir::Cache::archives="$DEBS" \
    -o APT::Install-Recommends=false \
    wine wine64 2>&1 | tail -3
  # extract only what wine needs (plus its deps that may be missing)
  for f in "$DEBS"/wine*.deb "$DEBS"/libwine*.deb "$DEBS"/winetricks*.deb; do
    [ -f "$f" ] && dpkg -x "$f" "$S" 2>/dev/null
  done
  WINE=$(wine_bin || true)
fi
[ -n "$WINE" ] || { log "FATAL: wine could not be installed"; exit 1; }
log "wine binary: $WINE"

# wine version banner (also warms the loader)
WINEVER=$(env HOME=/home/debian WINEPREFIX="$PREFIX_REL" WINEDEBUG=-all \
  "$BASE/bin/debian-session" "$WINE" --version 2>/dev/null | tail -1)
log "wine version: ${WINEVER:-unknown}"

# ---------------------------------------------------------- 2. WINEPREFIX
wenv() {  # run a command inside the sysroot with the wine environment
  env HOME=/home/debian USER=debian LOGNAME=debian \
      WINEPREFIX="$PREFIX_REL" WINEARCH=win64 \
      WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
      "$BASE/bin/debian-session" "$@"
}

if [ ! -d "$PREFIX/drive_c" ]; then
  log "creating WINEPREFIX (win64, ~1 min)"
  mkdir -p "$S/home/debian"
  wenv "$WINE" wineboot -i >/dev/null 2>&1
  # wineboot leaves a wineserver running; make it exit to free resources
  wenv "$WINE" wineserver -k 2>/dev/null
fi
[ -d "$PREFIX/drive_c" ] || { log "FATAL: WINEPREFIX creation failed"; exit 1; }
log "WINEPREFIX ready: $PREFIX_REL"

# ------------------------------------------------------------- 3. demo apps
sevenzip_done() { [ -x "$PREFIX/drive_c/Program Files/7-Zip/7zFM.exe" ]; }
npp_done()      { [ -x "$PREFIX/drive_c/Program Files/Notepad++/notepad++.exe" ]; }

if [ "${WINE_NO_APPS:-0}" != "1" ]; then
  gh_asset() {  # gh_asset <repo> <name-regex> -> asset browser_download_url
    curl -s --max-time 25 "https://api.github.com/repos/$1/releases/latest" \
      | python3 -c "
import json, re, sys
try:
    rel = json.load(sys.stdin)
    for a in rel.get('assets', []):
        if re.search(r'''$2''', a['name']):
            print(a['browser_download_url']); break
except Exception:
    pass"
  }

  if ! sevenzip_done; then
    log "installing 7-Zip (real Windows app, silent install)"
    URL=$(gh_asset ip7z/7zip '^7z[0-9]+-x64\.exe$' || true)
    [ -z "$URL" ] && URL=https://github.com/ip7z/7zip/releases/download/25.01/7z2501-x64.exe
    F="$DL/$(basename "$URL")"
    if [ ! -s "$F" ]; then curl -sL --retry 3 -o "$F" "$URL" || true; fi
    if [ -s "$F" ]; then
      # copy into the prefix-visible home so wine sees it via chroot paths
      mkdir -p "$S/home/debian/Downloads"
      cp -f "$F" "$S/home/debian/Downloads/"
      wenv "$WINE" "/home/debian/Downloads/$(basename "$F")" /S >/dev/null 2>&1
      wenv "$WINE" wineserver -k 2>/dev/null
      rm -f "$S/home/debian/Downloads/$(basename "$F")"
    fi
    sevenzip_done && log "7-Zip installed: $(basename "$URL")" \
                     || log "WARN: 7-Zip install failed"
  else
    log "7-Zip already installed"
  fi

  if ! npp_done; then
    log "installing Notepad++ (portable x64)"
    URL=$(gh_asset notepad-plus-plus/notepad-plus-plus '^npp\..*\.portable\.x64\.zip$' || true)
    F="$DL/$(basename "${URL:-npp.zip}")"
    if [ -n "$URL" ] && [ ! -s "$F" ]; then curl -sL --retry 3 -o "$F" "$URL" || true; fi
    if [ -s "$F" ]; then
      # unzip host-side with python (no deps), straight into the prefix
      python3 - "$F" "$PREFIX/drive_c/Program Files" <<'PY'
import sys, zipfile, os
zf, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zf) as z:
    names = sorted(z.namelist())
    tgt = os.path.join(dest, 'Notepad++')
    os.makedirs(tgt, exist_ok=True)
    for n in names:
        if n.endswith('/'):
            continue
        rel = n
        # strip a single top-level folder if the zip is not rooted at Notepad++
        parts = n.split('/')
        if parts[0].lower() != 'notepad++':
            rel = '/'.join(parts[1:])
        else:
            rel = '/'.join(parts[1:])
        if not rel:
            continue
        out = os.path.join(tgt, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, 'wb') as f:
            f.write(z.read(n))
print('notepad++ files:', len(os.listdir(tgt)))
PY
    fi
    npp_done && log "Notepad++ installed" || log "WARN: Notepad++ install failed"
  else
    log "Notepad++ already installed"
  fi
fi

# ------------------------------------------------ 4. host launcher (wine-run)
install -m 755 "$HERE/wine-run.sh" "$BASE/bin/wine-run" 2>/dev/null \
  || { log "FATAL: could not install $BASE/bin/wine-run"; exit 1; }
log "host launcher: $BASE/bin/wine-run"

# ------------------------------------------- 5. desktop (sysroot) bits
log "installing desktop helpers + launchers"
# -- chroot-side trampolines (curl the front-proxy, like android-start)
cat > "$S/usr/local/bin/wine-launch" <<'EOS'
#!/bin/bash
# wine-launch — desktop helper: start a Windows app via the front-proxy API.
out=$(curl -s -m 90 -X POST "http://127.0.0.1:3000/fapi/wine/app?name=${1:-winecfg}")
case "$out" in
  *'"ok":true'*|*'"ok": true'*)
    echo "Starting ${1} … (first launch takes a few seconds)";;
  *)
    echo "wine-launch failed: $out"; exit 1;;
esac
EOS
cat > "$S/usr/local/bin/wine-open" <<'EOS'
#!/bin/bash
# wine-open — file association: run a Windows executable with Wine.
f="${1:-}"
case "$f" in
  /home/debian/*) rel="${f#/home/debian/}";;
  *) echo "Only files inside your home folder can be run."; exit 1;;
esac
out=$(curl -s -m 90 -G -X POST "http://127.0.0.1:3000/fapi/wine/run" \
      --data-urlencode "src=$rel")
case "$out" in
  *'"ok":true'*|*'"ok": true'*)
    echo "Launching $(basename "$f") …";;
  *)
    echo "wine-open failed: $out"
    notify-send "Wine" "Could not launch $(basename "$f"): $out" 2>/dev/null
    exit 1;;
esac
EOS
chmod 755 "$S/usr/local/bin/wine-launch" "$S/usr/local/bin/wine-open"

# -- icons (generated once, kept in the script dir for reuse)
ICON_DIR="$HERE/icons"
if [ ! -f "$ICON_DIR/wine-config.png" ]; then
  log "generating launcher icons"
  python3 - "$ICON_DIR" <<'PY'
import os, sys
from PIL import Image, ImageDraw
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
S = 256
def icon(name, bg, glyph, size=110):
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([16, 16, S-16, S-16], radius=48, fill=bg)
    d.rounded_rectangle([16, 16, S-16, 76], radius=40, fill=(255, 255, 255, 38))
    d.text((S//2, S//2+6), glyph, fill='white', anchor='mm', font_size=size)
    img.save(os.path.join(out, name))
    print('made', name)
icon('wine-config.png',   (142, 45, 78), 'W')     # wine red
icon('wine-7zip.png',     (160, 34, 30), '7z')    # 7-zip red
icon('wine-notepadpp.png', (78, 155, 68), 'N+', 92)  # notepad++ green
PY
fi
mkdir -p "$S/usr/local/share/icons/hicolor/256x256/apps"
install -m 644 "$ICON_DIR"/wine-*.png \
  "$S/usr/local/share/icons/hicolor/256x256/apps/" 2>/dev/null

# -- desktop launchers
cat > "$S/usr/local/share/applications/wine-7zip.desktop" <<'EOS'
[Desktop Entry]
Version=1.0
Type=Application
Name=7-Zip (Windows)
Comment=7-Zip file manager — real Windows app running on Wine
Exec=/usr/local/bin/wine-launch 7zip
Icon=/usr/local/share/icons/hicolor/256x256/apps/wine-7zip.png
Terminal=false
Categories=Utility;Archiving;FileManager;
StartupNotify=true
EOS
cat > "$S/usr/local/share/applications/wine-notepadpp.desktop" <<'EOS'
[Desktop Entry]
Version=1.0
Type=Application
Name=Notepad++ (Windows)
Comment=Notepad++ source code editor — real Windows app running on Wine
Exec=/usr/local/bin/wine-launch notepad++
Icon=/usr/local/share/icons/hicolor/256x256/apps/wine-notepadpp.png
Terminal=false
Categories=Development;TextEditor;
StartupNotify=true
EOS
cat > "$S/usr/local/share/applications/wine-config.desktop" <<'EOS'
[Desktop Entry]
Version=1.0
Type=Application
Name=Wine Configuration
Comment=Configure the Windows compatibility layer (winecfg)
Exec=/usr/local/bin/wine-launch winecfg
Icon=/usr/local/share/icons/hicolor/256x256/apps/wine-config.png
Terminal=false
Categories=System;
StartupNotify=true
EOS
cat > "$S/usr/local/share/applications/wine-open.desktop" <<'EOS'
[Desktop Entry]
Version=1.0
Type=Application
Name=Run with Wine
Comment=Run a Windows executable (.exe / .msi) with Wine
Exec=/usr/local/bin/wine-open %f
Icon=/usr/local/share/icons/hicolor/256x256/apps/wine-config.png
Terminal=false
NoDisplay=true
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/x-msi;
EOS

# -- make .exe double-click open with Wine (default mime association)
mkdir -p "$S/home/debian/.config"
cat > "$S/home/debian/.config/mimeapps.list" <<'EOS'
[Default Applications]
application/x-ms-dos-executable=wine-open.desktop
application/x-msdownload=wine-open.desktop
application/x-msi=wine-open.desktop
EOS

# -- refresh desktop/icon caches inside the chroot
"$BASE/bin/debian-session" /usr/bin/update-desktop-database \
  /usr/share/applications 2>/dev/null || true
for d in "$S"/usr/share/icons/*; do
  [ -d "$d" ] || continue
  "$BASE/bin/debian-session" /usr/bin/gtk-update-icon-cache -q -t -f \
    "/usr/share/icons/$(basename "$d")" 2>/dev/null || true
done
log "desktop launchers installed (7-Zip, Notepad++, Wine config, Run-EXE)"

# ------------------------------------- 6. desktop shortcuts for the user
DB="$S/home/debian/Desktop"
mkdir -p "$DB"
cp "$S/usr/local/share/applications/wine-7zip.desktop"       "$DB/" 2>/dev/null
cp "$S/usr/local/share/applications/wine-notepadpp.desktop" "$DB/" 2>/dev/null
chmod +x "$DB"/wine-*.desktop 2>/dev/null

# mark launchers trusted (gvfs metadata, like android-runtime does)
GIO_SH="$S/usr/local/bin/.wine-trust.sh"
cat > "$GIO_SH" <<'EOS'
#!/bin/bash
export HOME=/home/debian
unset LD_PRELOAD
for f in /home/debian/Desktop/wine-*.desktop; do
  [ -f "$f" ] || continue
  for i in 1 2 3 4 5 6; do
    gio set "$f" metadata::trusted true 2>/dev/null
    gio info "$f" 2>/dev/null | grep -q 'metadata::trusted.*true' && break
    sleep 5
  done
  touch "$f"
done
EOS
chmod +x "$GIO_SH"
( setsid nohup "$BASE/bin/debian-session" /usr/local/bin/.wine-trust.sh \
    > "$BASE/run/wine-trust.log" 2>&1 < /dev/null & )

# --------------------------------------- 7. front-proxy must know /fapi/wine
if curl -s -m 5 http://127.0.0.1:3000/fapi/wine 2>/dev/null | grep -q '"installed"'; then
  log "front-proxy wine endpoints OK"
else
  NEW=$BASE/bin/front-proxy
  SRC=$(dirname "$HERE")/gnome-runtime/front-proxy.py
  [ -f "$SRC" ] || SRC=/home/z/my-project/scripts/gnome-runtime/front-proxy.py
  if [ -f "$SRC" ]; then
    log "updating front-proxy with wine endpoints + restarting it"
    cp "$SRC" "$NEW" && chmod +x "$NEW"
    pkill -f front-proxy 2>/dev/null   # supervisor revives it within ~6s
    sleep 8
  else
    log "WARN: front-proxy source with wine endpoints not found"
  fi
fi

# ------------------------------------------- 8. debian-status wine check
DS=$BASE/bin/debian-status
if [ -f "$DS" ] && ! grep -q 'wine runtime' "$DS"; then
  cat >> "$DS" <<'EOS'

# Windows app runtime (Wine, native sysroot packages)
if [ -x "$BASE/sysroot/usr/bin/wine" ] || [ -x "$BASE/sysroot/usr/bin/wine-stable" ] || [ -x "$BASE/sysroot/usr/bin/wine64" ]; then
  ok "wine runtime installed (Windows programs supported)"
else
  bad "wine runtime not installed"
fi
EOS
  log "debian-status: wine check added"
fi

# ------------------------------------------------------------- 9. self-test
log "self-test:"
echo "  wine      : ${WINEVER:-?} ($WINE)"
echo "  prefix    : $([ -d "$PREFIX/drive_c" ] && echo OK || echo MISSING)"
echo "  7-Zip     : $(sevenzip_done && echo OK || echo missing)"
echo "  Notepad++ : $(npp_done && echo OK || echo missing)"
FAPI=$(curl -s -m 5 http://127.0.0.1:3000/fapi/wine 2>/dev/null | head -c 200)
echo "  fapi/wine : ${FAPI:-unreachable}"
log "done."
