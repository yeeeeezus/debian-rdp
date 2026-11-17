#!/bin/bash
# install-sdnc.sh - (re)install the Ryu SDN controller + lecture compat into
# the live sysroot after a reset. Idempotent. Usage: bash install-sdnc.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
S=/home/z/debian/sysroot

# 1. ryu + python deps (packed, py3.13) -> ~/.local
mkdir -p "$S/home/debian/.local/lib/python3.13" "$S/home/debian/.local/bin"
tar -xzf "$HERE/py-sdnc/ryu-and-deps.tar.gz" \
    -C "$S/home/debian/.local/lib/python3.13/"
# the tarball has bin/ inside .local already (rolled with two -C)
chmod +x "$S/home/debian/.local/bin/ryu-manager" 2>/dev/null || true
cp "$S/home/debian/.local/bin/ryu-manager" "$S/usr/local/bin/ryu-manager"
chmod 755 "$S/usr/local/bin/ryu-manager"

# 2. compat layer + labrc updates
for f in lecture_compat.py sitecustomize.py; do
  cp "$HERE/$f" "$S/usr/local/lib/mininet-lab/$f"
done
cp "$HERE/labrc" "$S/usr/local/lib/mininet-lab/labrc"
cp "$HERE/mininet-lab" "$S/usr/local/bin/mininet-lab" && chmod 755 "$S/usr/local/bin/mininet-lab"

# 3. lecture scripts -> ~/mininet-labs (+ Desktop copy)
mkdir -p "$S/home/debian/mininet-labs" "$S/home/debian/Desktop/mininet-labs"
cp "$HERE/lecture-examples/"*.py "$S/home/debian/mininet-labs/"
cp "$HERE/lecture-examples/"*.py "$S/home/debian/Desktop/mininet-labs/"
cp "$HERE/lecture-examples/README.md" "$S/home/debian/mininet-labs/" 2>/dev/null || true

# 4. CA bundle for pip (ca-certificates postinst doesn't run under fakechroot)
[ -s "$S/etc/ssl/certs/ca-certificates.crt" ] || \
  cp /etc/ssl/certs/ca-certificates.crt "$S/etc/ssl/certs/ca-certificates.crt" 2>/dev/null || true

echo "SDN controller installed: ryu-manager (listening on :6653 when run)"
echo "Lecture compat: OVSSwitch->LxBr, RemoteController->stub, loop-guard on rings"
echo "Lecture scripts: ~/mininet-labs (run inside 'mininet-lab')"
