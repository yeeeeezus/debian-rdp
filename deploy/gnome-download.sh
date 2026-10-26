#!/bin/bash
# ============================================================================
# Debian 13 (trixie) GNOME edition download - unprivileged user
# Downloads the full dependency closure of:
#   GNOME 49 desktop (Debian's OFFICIAL default GUI) + GNOME apps
#   + the existing free software suite (kept from the KDE build)
#   + Remmina/RDP client (for the Windows RDP container)
#   + the VNC serving stack (TigerVNC / noVNC / websockify)
# for extraction into /home/z/debian/sysroot (run under fakechroot).
# Self-healing: packages missing from trixie are dropped automatically.
# Cached debs in /home/z/debian/debs are skipped (incremental).
# ============================================================================
set -u
BASE=/home/z/debian
DEBS=$BASE/debs
LISTS=$BASE/aptlists
EMPTY_STATUS=$BASE/empty-status
mkdir -p "$DEBS/partial" "$LISTS/partial" "$BASE/sysroot" "$BASE/logs"
: > "$EMPTY_STATUS"

echo "[$(date +%T)] Refreshing user-owned apt lists..."
apt-get -o Debug::NoLocking=1 \
  -o Dir::State::lists="$LISTS" \
  -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/debian.sources \
  -o Dir::Etc::sourceparts=/nonexistent \
  -o Dir::Cache="$LISTS" \
  -o APT::Get::List-Cleanup=0 \
  update 2>&1 | tail -2

PKGS=(
  # --- ESSENTIAL base (apt never pulls Essential pkgs into dep chains!) ---
  base-files base-passwd bash coreutils dash debianutils diffutils dpkg
  findutils grep gzip hostname login mawk ncurses-base ncurses-bin passwd
  perl-base procps sed sysvinit-utils tar util-linux mount bsdutils
  e2fsprogs iproute2 ca-certificates libc-bin
  # --- GNOME 49 session core (the official Debian desktop) ---
  gnome-core gnome-shell gnome-session-bin gnome-settings-daemon
  gnome-control-center gnome-keyring seahorse
  nautilus gnome-terminal ptyxis gnome-text-editor gnome-tweaks dconf-editor
  gnome-shell-extension-desktop-icons-ng xdg-user-dirs-gtk
  desktop-base gnome-backgrounds
  # --- official GNOME apps ---
  gnome-calculator gnome-calendar gnome-clocks gnome-characters
  gnome-font-viewer gnome-logs gnome-disk-utility
  # --- session infrastructure ---
  xdg-user-dirs xdg-utils dbus dbus-x11 x11-xserver-utils x11-utils xterm
  libgl1-mesa-dri mesa-utils locales
  # --- fonts ---
  fonts-inter fonts-jetbrains-mono fonts-noto-core fonts-noto-ui-core
  fonts-noto-color-emoji fonts-liberation2
  # --- Qt under GNOME theming + KDE apps (kept from previous build) ---
  qt6-gtk-platformtheme
  dolphin konsole kate okular gwenview ark kcalc kde-spectacle kio-extras
  kpat kmines ksudoku
  # --- fakechroot runtime (runs the whole sysroot without root) ---
  fakechroot proot
  # --- VNC / web serving stack ---
  tigervnc-standalone-server tigervnc-tools novnc websockify python3-websockify
  # --- internet ---
  firefox-esr thunderbird filezilla openssh-client
  remmina remmina-plugin-rdp remmina-plugin-vnc freerdp2-x11
  # --- office ---
  libreoffice libreoffice-gtk3
  # --- media ---
  vlc ffmpeg
  # --- graphics ---
  gimp
  # --- network lab ---
  mininet wireshark nmap iperf3 tcpdump net-tools iputils-ping ethtool
  # --- development ---
  build-essential cmake git python3-pip python3-venv python3-tk
  # --- utilities ---
  qbittorrent fastfetch htop p7zip-full zip unzip unrar-free vim nano less
  file curl wget bc rsync bash-completion
  # --- remote desktop experience ---
  autocutsel xclip tree
)

# self-healing resolve loop: drop whatever trixie doesn't have
for attempt in 1 2 3 4 5; do
  echo "[$(date +%T)] Download attempt $attempt with ${#PKGS[@]} packages..."
  OUT=$(apt-get install --download-only -y \
    -o Debug::NoLocking=1 \
    -o Dir::State::lists="$LISTS" \
    -o Dir::State::status="$EMPTY_STATUS" \
    -o Dir::Cache::archives="$DEBS" \
    -o APT::Install-Recommends=false \
    "${PKGS[@]}" 2>&1)
  RC=$?
  echo "$OUT" | tail -6
  BAD=$(echo "$OUT" | grep -oP "Unable to locate package '?\K[^ ']+" | sort -u)
  if [ -z "$BAD" ]; then
    echo "[$(date +%T)] apt-get finished (rc=$RC)"
    break
  fi
  echo "Dropping missing packages: $(echo $BAD)"
  NEW=()
  for p in "${PKGS[@]}"; do
    skip=0
    for b in $BAD; do [ "$p" = "$b" ] && skip=1; done
    [ $skip -eq 0 ] && NEW+=("$p")
  done
  PKGS=("${NEW[@]}")
done

DEBCOUNT=$(ls "$DEBS"/*.deb 2>/dev/null | wc -l)
SIZE=$(du -sh "$DEBS" 2>/dev/null | cut -f1)
echo "=== [$(date +%T)] DONE: $DEBCOUNT deb files, total $SIZE ==="
